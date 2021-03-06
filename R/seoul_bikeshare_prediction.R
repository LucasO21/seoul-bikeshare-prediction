# SEOUL BIKE SHARING DEMAND PREDICTION ----

# Data Source: # "https://archive.ics.uci.edu/ml/machine-learning-databases/00560/SeoulBikeData.csv"

# 1.0: Setup ----

# * Libraries ----
library(tidyverse)
library(lubridate)
library(skimr)
library(plotly)
library(DT)
library(tidymodels)
library(rules)
library(vip)
library(tictoc)
library(future)
library(doFuture)
library(parallel)

# * Load Dataset ----
colnames <-  c("date", "rented_count", "hour", "temp", "humidity", "windspeed", "visibility", 
               "dew_point", "solar_rad", "rainfall", "snowfall", "season", "holiday", "functional_day")

seoul_bikes_raw_tbl <- read.csv("01-Data/SeoulBikeData.csv", header = F, skip = 1) %>% 
    as_tibble() %>% 
    setNames(colnames)


# * Data Inspection ----
seoul_bikes_raw_tbl %>% glimpse()

dim(seoul_bikes_raw_tbl)

seoul_bikes_raw_tbl %>% sapply(function(x)sum(is.na(x)))


# 2.0: Exploratory Data Analysis ----

# * Numeric Variables ----
seoul_bikes_raw_tbl %>% 
    select_if(is.numeric) %>% 
    head()

# * Categorical Variables ----
seoul_bikes_raw_tbl %>% 
    select_if(is.character) %>% 
    head()

# * Skim ----
skim(seoul_bikes_raw_tbl)

# * Format Data ----
seoul_bikes_tbl <- seoul_bikes_raw_tbl %>% 
    
    # # add date features
    mutate(date = dmy(date)) %>% 
    mutate(day_of_week = wday(date, label = TRUE) %>% as.factor) %>% 
    mutate(month = month(date, label = TRUE) %>% as.factor) %>% 
    mutate_if(is.character, as.factor) %>% 
    
    # filter function_day = "yes"
    filter(functional_day == "Yes")
    
# * Overall Distribution of Rented Count ----
seoul_bikes_tbl %>% 
    ggplot(aes(rented_count))+
    geom_histogram(color = "white", fill = "grey50", binwidth = 50)+
    labs(title = "Distribution of Rented Count",
         x = "Rented Count",
         y = "Frequency")+
    theme_bw()
    
# * Hourly Distribution of Rented Count ----
seoul_bikes_tbl %>% 
    mutate(hour = as.factor(hour)) %>% 
    ggplot(aes(hour,rented_count))+
    geom_boxplot(color = "grey30", fill = "grey80", outlier.colour = "red")+
    # scale_x_continuous(limits = c(0, 23), breaks = seq(0, 23, by = 1))+
    labs(title = "Bike Rentals by Hour of Day",
         x = "Hour of Day",
         y = "Rented Count")+
    theme_bw()

# * Daily Distribution of Rented Count ----
seoul_bikes_tbl %>% 
    ggplot(aes(day_of_week, rented_count))+
    geom_boxplot(color = "grey30", fill = "grey80", outlier.colour = "red")+
    theme_bw()+
    labs(title = "Daily Rented Count",
         subtitle = "More rentals on Mondays, Wednesdays & Fridays",
         y = "Rented Count",
         x = "Day of Week")


# * Hourly Rental Distribution by Season ----
seoul_bikes_tbl %>% 
    mutate(hour = as.factor(hour)) %>% 
    ggplot(aes(hour,rented_count))+
    geom_boxplot(color = "grey30", fill = "grey80", outlier.colour = "red")+
    facet_wrap(~ season, "free")+
    labs(title = "Bike Rentals by Hour of Day",
         x = "Hour",
         y = "Rental Count")+
    theme_bw()+
    theme(axis.text = element_text(size = 8))

# * Daily Rental Distribution by Season ----
seoul_bikes_tbl %>% 
    mutate(hour = as.factor(hour)) %>% 
    ggplot(aes(day_of_week,rented_count))+
    geom_boxplot(color = "grey30", fill = "grey80", outlier.colour = "red")+
    facet_wrap(~ season, "free")+
    labs(title = "Bike Rentals by Hour of Day",
         x = "Hour",
         y = "Rental Count")+
    theme_bw()+
    theme(axis.text = element_text(size = 8))


# * Rented Count vs Temp / Season ----
seoul_bikes_tbl %>% 
    ggplot(aes(temp, rented_count, color = season))+
    geom_point(alpha = 0.5)+
    theme_bw()+
    labs(title = "Rented Count vs Temp", y = "Rented Count", x = "Temp")

# *  Correlation Matrix ----
cor_matrix <- seoul_bikes_tbl %>% 
    select_if(is.numeric) %>% 
    cor() %>% 
    round(2) %>% 
    reshape2::melt()

cor_matrix %>% 
    ggplot(aes(Var1, Var2, fill = value))+
    geom_tile(color = "white")+
    scale_fill_gradient2(low = "grey69", high = "grey31", mid = "white",
                         midpoint = 0, limit = c(-1, 1), space = "lab")+
    theme_bw()+
    geom_text(aes(label = value))+
    labs(title = "Correlation Heatmap",
         subtitle = "", x = "", y = "")+
    theme(axis.text.x = element_text(angle = 35, hjust = 1))


# * Distribution of Other Numeric Weather Features ----
seoul_bikes_tbl %>% 
    select_if(is.numeric) %>% 
    select(-rented_count, -hour) %>% 
    gather() %>% 
    ggplot(aes(value))+
    geom_histogram(color = "white", fill = "grey50")+
    facet_wrap(~ key, scales = "free")+
    theme_bw()
    
    

# 3.0: Modeling ----

# * 3.1: Data Splitting ----
set.seed(100)
split_obj <- initial_split(seoul_bikes_tbl, prop = 0.80, strata = rented_count)

train_tbl <- training(split_obj)
test_tbl  <- testing(split_obj)

# * 3.2: Cross Validation Specs ----
set.seed(101)
resamples_obj <- vfold_cv(seoul_bikes_tbl, v = 10)


# * 3.3: Recipes ----

# Random Forest Recipe Spec
ranger_recipe <- recipe(rented_count ~ ., data = train_tbl) %>% 
    step_rm(date, functional_day) %>% 
    step_zv(all_predictors())

# Xgboost Recipe Spec
xgboost_recipe <- recipe(formula = rented_count ~ ., data = seoul_bikes_tbl) %>% 
    step_rm(date, functional_day) %>% 
    step_novel(all_nominal(), -all_outcomes()) %>% 
    step_dummy(all_nominal(), -all_outcomes(), one_hot = TRUE) %>% 
    step_zv(all_predictors())

# Cubist Recipe Spec
cubist_recipe <- recipe(formula = rented_count ~ ., data = seoul_bikes_tbl) %>% 
    step_rm(date, functional_day) %>% 
    step_zv(all_predictors()) %>% 
    prep()


# * 3.4: Model Specs ----

# Random Forest Model Spec
ranger_spec <- rand_forest(
    mtry  = tune(),
    min_n = tune(),
    trees = 1000
) %>%
    set_mode("regression") %>%
    set_engine("ranger") 

# Xgboost Model Spec
xgboost_spec <-boost_tree(
    trees          = tune(),
    min_n          = tune(),
    tree_depth     = tune(),
    learn_rate     = tune(),
    loss_reduction = tune(),
    sample_size    = tune()
) %>%
    set_mode("regression") %>%
    set_engine("xgboost") 

# Cubist Model Spec
cubist_spec <- cubist_rules(
    committees = tune(), 
    neighbors  = tune()
) %>%
    set_engine("Cubist") 


# * 3.1: Workflows ----

# Random Forest Workflow
ranger_workflow <- 
    workflow() %>% 
    add_recipe(ranger_recipe) %>% 
    add_model(ranger_spec) 

# Xgboost Workflow
xgboost_workflow <- 
    workflow() %>% 
    add_recipe(xgboost_recipe) %>% 
    add_model(xgboost_spec) 

# Cubist Workflow
cubist_workflow <- 
    workflow() %>% 
    add_recipe(cubist_recipe) %>% 
    add_model(cubist_spec) 


# 4.0: Hyper-Parameter Tuning Round 1 ----

# * 4.1: Setup Parallel Processing ----
registerDoFuture()
n_cores <- detectCores()
plan(strategy = cluster, workers = makeCluster(n_cores))

# * 4.2: Random Forest Tuning ----
tic()
set.seed(456)
ranger_tune_results_1 <- tune_grid(
    object    = ranger_workflow, 
    resamples = resamples_obj,
    grid      = grid_latin_hypercube(
                        parameters(ranger_spec) %>% 
                            update(mtry = mtry(range = c(1, 14))),
                        size = 15),
    control   = control_grid(save_pred = TRUE, verbose = FALSE, allow_par = TRUE),
    metrics   = metric_set(mae, rmse, rsq)
)
toc()

# Random Forest Round 1 Results
ranger_tune_results_1 %>% show_best("mae", n = 5)

# Save Model For Future Use
write_rds(ranger_tune_results_1, file = "02-Models/ranger_tune_results_1.rds")


# * 4.3: Xgboost Tuning Round 1----
tic()
set.seed(456)
xgboost_tune_results_1 <- tune_grid(
    object    = xgboost_workflow, 
    resamples = resamples_obj,
    grid      = grid_latin_hypercube(parameters(xgboost_spec),
                                     size = 15),
    control   = control_grid(save_pred = TRUE, verbose = FALSE, allow_par = TRUE),
    metrics   = metric_set(mae, rmse, rsq)
)
toc()

# Xgboost Round 1 Results
xgboost_tune_results_1 %>% show_best("rmse", n = 5)

# Save Model For Future Use
write_rds(xgboost_tune_results_1, file = "02-Models/xgboost_tune_results_1.rds")


# * 4.3: Cubist Tuning Round 1 ----
tic()
set.seed(456)
cubist_tune_results_1 <- tune_grid(
    object    = cubist_workflow, 
    resamples = resamples_obj,
    grid      = grid_latin_hypercube(parameters(cubist_spec),
                                     size = 15),
    control   = control_grid(save_pred = TRUE, verbose = FALSE, allow_par = TRUE),
    metrics   = metric_set(mae, rmse, rsq)
)
toc()


# Cubist Round 1 Results
cubist_tune_results_1 %>% show_best("rmse", n = 5)

# Save Model For Future Use
write_rds(cubist_tune_results_1, file = "02-Models/cubist_tune_results_1.rds")

# Loading Saved Models
# ranger_tune_results_1 <- read_rds("02-Models/ranger_tune_results_1.rds")
# xgboost_tune_results_1 <- read_rds("02-Models/xgboost_tune_results_1.rds")
# cubist_tune_results_1 <- read_rds("02-Models/cubist_tune_results_1.rds")


# * 4.4: Training Results Metrics Comparison ----

# Function To Get Model Model Metrics
func_get_best_metric <- function(model, model_name){
    
    bind_rows(
        model %>% show_best("mae", 1),
        model %>% show_best("rmse", 1),
        model %>% show_best("rsq", 1) 
    ) %>% 
        mutate(mean = round(mean, 2)) %>% 
        select(.metric, mean) %>% 
        spread(key = .metric, value = mean) %>% 
        mutate(model := {{model_name}}) %>% 
        select(model, everything(.))
}

ranger_metrics_1 <- func_get_best_metric(ranger_tune_results_1, "Random Forest")
xgboost_metrics_1 <- func_get_best_metric(xgboost_tune_results_1, "XGBOOST")
cubist_metrics_1 <- func_get_best_metric(cubist_tune_results_1, "Cubist")

# Training Set Metrics Table
training_metrics_1 <- bind_rows(
    ranger_metrics_1,
    xgboost_metrics_1,
    cubist_metrics_1
) %>% 
    arrange(rmse) %>% 
    datatable(
        class = "cell-border stripe",
        caption = "Training Set Metrics Round 1",
        options = list(
            dom = "t"
        )
        
    )

training_metrics_1


# 5.0: Hyper-Parameter Tuning Round 2 ----

# * XGBOOST Tuning Round 2 ----

# Visualize XGBOOST Tuning Params
p <- xgboost_tune_results_1 %>% 
    autoplot()+
    theme_bw()+
    labs(title = "XGBOOST Tuning Parameters")

ggplotly(p) 


# Updated XGBOOST Grid 
set.seed(123)
grid_spec_xgboost_round_2 <- grid_latin_hypercube(
    parameters(xgboost_spec) %>% 
        update(
            trees = trees(range = c(1280, 1965)),
            learn_rate = learn_rate(range = c(-2.45, -1.45))),
    size = 15
)

# Tuning Round 2
tic()
set.seed(654)
xgboost_tune_results_2 <- tune_grid(
    object    = xgboost_workflow, 
    resamples = resamples_obj,
    grid      = grid_spec_xgboost_round_2,
    control   = control_grid(save_pred = TRUE, verbose = FALSE, allow_par = TRUE),
    metrics   = metric_set(mae, rmse, rsq)
)
toc()

# * 5.1: Xgboost Round 2 Results ----
xgboost_tune_results_2 %>% show_best("rmse", n = 5)

# Save Model For Future Use
write_rds(xgboost_tune_results_2, file = "02-Models/xgboost_tune_results_2.rds")


# * 5.2: Cubist Tuning Round 2 ----

# Visualize Cubist Tuning Params
p <- cubist_tune_results_1 %>% 
    autoplot()+
    theme_bw()+
    labs(title = "Cubist Tuning Parameters")

ggplotly(p) 

# Updated Cubist Grid 
set.seed(123)
grid_spec_cubist_round_2 <- grid_latin_hypercube(
    parameters(cubist_spec) %>% 
        update(
            committees = committees(range = c(15, 98)),
            neighbors = neighbors(range = c(2, 7))),
    size = 15
)

# Tuning Round 2
tic()
set.seed(654)
cubist_tune_results_2 <- tune_grid(
    object    = cubist_workflow, 
    resamples = resamples_obj,
    grid      = grid_spec_cubist_round_2,
    control   = control_grid(save_pred = TRUE, verbose = FALSE, allow_par = TRUE),
    metrics   = metric_set(mae, rmse, rsq)
)
toc()

# Cubist Round 2 Results
cubist_tune_results_2 %>% show_best("mae", n = 5)

# Save Model For Future Use
write_rds(cubist_tune_results_2, file = "02-Models/cubist_tune_results_2rds")


# Loading Saved Models
# xgboost_tune_results_2 <- read_rds("02-Models/xgboost_tune_results_2.rds")
# cubist_tune_results_2 <- read_rds("02-Models/cubist_tune_results_2rds")

# * 5.3 Training Results Metrics Comparison Round 2 ----
xgboost_metrics_2 <- func_get_best_metric(xgboost_tune_results_2, "XGBOOST")
cubist_metrics_2 <- func_get_best_metric(cubist_tune_results_2, "Cubist")

# Training Set Metrics Table
training_metrics_2 <- bind_rows(
    xgboost_metrics_2,
    cubist_metrics_2,
) %>% 
    arrange(rmse) %>% 
    datatable(
        class = "cell-border stripe",
        caption = "Training Set Metrics Round 2",
        options = list(
            dom = "t"
        )
        
    )

training_metrics_2




# 6.0: Finalize Models ----

# * XGBOOST Final Fit ----
xgboost_spec_final <- xgboost_spec %>% 
    finalize_model(parameters = xgboost_tune_results_2 %>% select_best("rmse"))

set.seed(123)
xgboost_last_fit <- workflow() %>% 
    add_model(xgboost_spec_final) %>% 
    add_recipe(xgboost_recipe) %>% 
    last_fit(split_obj, metric_set(mae, rmse, rsq))

# XGBOOST Final Fit (Test Set) Metrics
collect_metrics(xgboost_last_fit)


# * Cubist Final Fit ----
cubist_spec_final <- cubist_spec %>% 
    finalize_model(parameters = cubist_tune_results_2 %>% select_best("rmse"))

set.seed(123)
cubist_last_fit <- workflow() %>% 
    add_model(cubist_spec_final) %>% 
    add_recipe(cubist_recipe) %>% 
    last_fit(split_obj, metric_set(mae, rmse, rsq))

# Cubist Final Fit (Test Set) Metrics
collect_metrics(cubist_last_fit)

# 6.1: Test Results Metrics Comparison ----

# Final Fit (Test) Set Metrics Set (XGBOOST)
xgboost_test_metrics <- collect_metrics(xgboost_last_fit) %>% 
    select(-.config) %>% 
    bind_rows(
        xgboost_last_fit %>% 
            collect_predictions() %>% 
            mae(rented_count, .pred) 
    ) %>% 
    select(-.estimator) %>% 
    mutate(model = "XGBOOST") %>% 
    arrange(.estimate)

# Final Fit (Test) Set Metrics Set (Cubist)
cubist_test_metrics <- collect_metrics(cubist_last_fit) %>% 
    select(-.config) %>% 
    bind_rows(
        cubist_last_fit %>% 
            collect_predictions() %>% 
            mae(rented_count, .pred) 
    ) %>% 
    select(-.estimator) %>% 
    mutate(model = "Cubist") %>% 
    arrange(.estimate)

# Final Fit (Test) Set Metrics Table
test_set_metrics <- bind_rows(
    xgboost_test_metrics,
    cubist_test_metrics
) %>% 
    mutate(.estimate = round(.estimate, 2)) %>% 
    spread(key = .metric, value = .estimate) %>% 
    arrange(mae) %>% 
    datatable(
        class = "cell-border stripe",
        caption = "Test Set Metrics",
        options = list(
            dom = "t"
        )
        
    )


# 7.0: Making Predictions ----

#* To make predictions, we'll use the model offering the best rmse which is the
#* XGBOOST. We'll need to -
#* 1) Train the model on the entire dataset
#* 2) Predict on future data

# * 7.1: Train Model on Entire Data ----
xgboost_model <- xgboost_spec_final %>% 
    fit(rented_count ~ ., data = xgboost_recipe %>% prep %>% bake(new_data = seoul_bikes_tbl))

# * 7.2: Create Sample New Data For Prediction ----
sample_data <- 
    tibble(
        date = ymd("2019-01-24"),
        hour = 6,
        temp = 6,
        humidity = 80, 
        windspeed = 1.8,
        visibility = 1400,
        dew_point = -6.0,
        solar_rad = 0.00,
        rainfall = 0.0,
        snowfall = 0.0,
        season = "Autumn",
        holiday = "No Holiday",
        functional_day = "Yes",
        day_of_week = wday(date, label = TRUE),
        month = month(date, label = TRUE)
    )

sample_data <- sample_data %>% 
    mutate_if(is.character, as.factor)

sample_data

# 7.3: Predictions
xgboost_recipe %>% 
    prep() %>% 
    bake(new_data = sample_data) %>% 
    predict(xgboost_model, new_data = .)

# 8.0: Variable Importance ----
vip_plot <- vip(xgboost_model)+
    theme_bw()+
    labs(title = "XGBOOST Model Variable Importance")

vip_plot
