library(tidyverse)

new_orleans_restaurants <- readRDS("data/new_orleans/business_new_orleans.rds")

# one row per business-category pair, cleaned
restaurant_categories <- new_orleans_restaurants |>
  select(business_id, business_name, categories) |>
  separate_longer_delim(categories, delim = ",") |>
  mutate(category = str_to_lower(str_squish(categories))) |>
  select(-categories) |>
  filter(!category %in% c("restaurants", "food")) |>   # every row has these, so they tell us nothing
  distinct()

category_counts <- restaurant_categories |>
  count(category, name = "number_of_restaurants", sort = TRUE)

category_counts |> print(n = 40)

# pair every category with every other category at the same restaurant
category_pairs <- restaurant_categories |>
  select(business_id, category) |>
  inner_join(
    restaurant_categories |> select(business_id, category),
    by = "business_id",
    relationship = "many-to-many"
  ) |>
  filter(category.x < category.y) |>     
  count(category.x, category.y, name = "restaurants_with_both", sort = TRUE)

# 1. What appears most often alongside seafood?
category_pairs |>
  filter(category.x == "seafood" | category.y == "seafood") |>
  slice_head(n = 10)

# 2. What appears most often alongside cajun/creole?
category_pairs |>
  filter(category.x == "cajun/creole" | category.y == "cajun/creole") |>
  slice_head(n = 10)

selected_categories <- c("seafood", "cajun/creole", "southern", "soul food")


category_pairs |>
  filter(category.x %in% selected_categories,
         category.y %in% selected_categories)


selected_restaurants <- new_orleans_restaurants |>
  semi_join(
    restaurant_categories |> filter(category %in% selected_categories),
    by = "business_id"
  )

nrow(selected_restaurants)

saveRDS(selected_restaurants,
        "data/new_orleans/selected_restaurants.rds",
        compress = "xz")


new_orleans_reviews <- readRDS("data/new_orleans/reviews_new_orleans_notext.rds")

category_reviews <- new_orleans_reviews |>
  semi_join(selected_restaurants, by = "business_id") |>
  mutate(review_date = ymd_hms(date), 
         review_year = year(review_date))


restaurant_reviews <- selected_restaurants |>
  select(business_id, business_name, stars_business = stars) |>
  inner_join(category_reviews, by = "business_id",
             relationship = "one-to-many")

nrow(category_reviews)
n_distinct(category_reviews$business_id)
sum(is.na(category_reviews$review_date))

saveRDS(category_reviews,
        "data/new_orleans/category_reviews.rds",
        compress = "xz")
