library(tidyverse)
library(jsonlite)

business_file <- "data/raw/yelp_academic_dataset_business.json"


business_raw <- stream_in(file(business_file), verbose = FALSE)


business <- business_raw |>
  as_tibble() |>
  select(business_id, name, address, city, state, postal_code,
         latitude, longitude, stars, review_count, categories)

dim(business_raw)
dim(business)
glimpse(business)


rm(business_raw)
gc()

# every city label in Louisiana
business |>
  filter(state == "LA") |>
  count(city, sort = TRUE) |>
  print(n = 30)

# any spelling variants of New Orleans, in any state
business |>
  filter(str_detect(city, regex("orleans|nola", ignore_case = TRUE))) |>
  count(state, city, sort = TRUE)

new_orleans_restaurants <- business |>
  filter(
    state == "LA",
    str_to_lower(str_squish(city)) == "new orleans",   # catches NEW ORLEANS, new orleans, etc.
    !is.na(categories),
    str_detect(categories, regex("Restaurants", ignore_case = TRUE))
  ) |>
  mutate(
    postal_code = na_if(postal_code, ""),
    categories = str_squish(categories),
    business_name = str_squish(name)
  ) |>
  distinct(business_id, .keep_all = TRUE)

new_orleans_restaurants |>
  summarise(
    number_of_restaurants = n(),
    missing_latitude = sum(is.na(latitude)),
    missing_longitude = sum(is.na(longitude)),
    missing_postal_code = sum(is.na(postal_code))
  )

saveRDS(
  new_orleans_restaurants,
  "data/new_orleans/business_new_orleans.rds",
  compress = "xz"
)

# confirm it reads back the same
check <- readRDS("data/new_orleans/business_new_orleans.rds")
identical(check, new_orleans_restaurants)
file.size("data/new_orleans/business_new_orleans.rds") / 1e6   # size in MB

new_orleans_restaurants |>
  summarise(missing_longitude = sum(is.na(longitude)),
            missing_postal_code = sum(is.na(postal_code)))

nola_ids <- new_orleans_restaurants$business_id
review_file <- "data/raw/yelp_academic_dataset_review.json"
review_chunks <- list()

start_time <- Sys.time()

stream_in(
  file(review_file),
  handler = function(chunk) {
    keep <- chunk |>
      filter(business_id %in% nola_ids) |>
      select(review_id, business_id, user_id, stars, date, text, useful, funny, cool)
    review_chunks[[length(review_chunks) + 1]] <<- keep   # <<- saves to the list outside the function
  },
  pagesize = 50000,
  verbose = TRUE   # prints a progress counter
)

end_time <- Sys.time()
end_time - start_time   # record this for your report

new_orleans_reviews <- bind_rows(review_chunks) |> as_tibble()
rm(review_chunks)
gc()

dim(new_orleans_reviews)
n_distinct(new_orleans_reviews$business_id)


# 1. any duplicate reviews?
sum(duplicated(new_orleans_reviews$review_id))

# 2. compare with Yelp's own review_count field
sum(new_orleans_restaurants$review_count)

# 3. any missing values in key columns?
new_orleans_reviews |>
  summarise(across(c(business_id, user_id, stars, date), ~ sum(is.na(.x))))

# 4. date range
range(new_orleans_reviews$date)

saveRDS(
  new_orleans_reviews,
  "data/new_orleans/reviews_new_orleans.rds",
  compress = "xz"
)

file.size("data/new_orleans/reviews_new_orleans.rds") / 1e6   # size in MB

reviews_no_text <- new_orleans_reviews |>
  select(-text)

saveRDS(
  reviews_no_text,
  "data/new_orleans/reviews_new_orleans_notext.rds",
  compress = "xz"
)

file.size("data/new_orleans/reviews_new_orleans_notext.rds") / 1e6
