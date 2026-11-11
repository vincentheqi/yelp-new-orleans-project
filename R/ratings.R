# ---- Robustness check: does one restaurant drive the top neighborhoods? ----
# Tulane–Gravier had the highest adjusted score, but only 5 rankable restaurants.
# Leave-one-out: recompute each neighborhood's score without its best restaurant.

library(tidyverse)
library(sf)

selected_points  <- readRDS("data/new_orleans/selected_points.rds")
category_reviews <- readRDS("data/new_orleans/category_reviews.rds")

# keep only reviews for the 658 restaurants inside the official city boundary
category_reviews <- category_reviews |>
  semi_join(st_drop_geometry(selected_points), by = "business_id")

nrow(category_reviews)
n_distinct(category_reviews$user_id)


all_reviewer_summary <- category_reviews |>
  group_by(business_id) |>
  summarise(
    number_of_reviews_all_reviewers = n(),
    average_stars_all_reviewers     = mean(stars),
    median_stars_all_reviewers      = median(stars),
    .groups = "drop"
  )

all_reviewer_summary |>
  left_join(st_drop_geometry(selected_points) |> select(business_id, business_name),
            by = "business_id") |>
  arrange(desc(average_stars_all_reviewers)) |>
  slice_head(n = 10)

reviewer_activity <- category_reviews |>
  count(user_id, name = "reviews_in_selected_categories")

# how many reviewers and reviews survive each possible threshold?
threshold_table <- tibble(threshold = c(1, 2, 3, 5, 10, 20)) |>
  mutate(
    reviewers_kept      = map_int(threshold, ~ sum(reviewer_activity$reviews_in_selected_categories >= .x)),
    pct_reviewers_kept  = reviewers_kept / nrow(reviewer_activity) * 100,
    reviews_kept        = map_int(threshold, ~ sum(reviewer_activity$reviews_in_selected_categories[
      reviewer_activity$reviews_in_selected_categories >= .x])),
    pct_reviews_kept    = reviews_kept / nrow(category_reviews) * 100
  )

threshold_table

eligible_reviewers <- reviewer_activity |>
  filter(reviews_in_selected_categories >= 5)

# each reviewer's usual rating within our 658 restaurants
reviewer_baselines <- category_reviews |>
  group_by(user_id) |>
  summarise(
    reviewer_mean         = mean(stars),
    reviewer_median       = median(stars),
    reviewer_review_count = n(),
    .groups = "drop"
  )

category_reviews_adjusted <- category_reviews |>
  left_join(reviewer_baselines, by = "user_id") |>
  mutate(
    normalized_mean_score   = stars - reviewer_mean,
    normalized_median_score = stars - reviewer_median
  )

eligible_adjusted_reviews <- category_reviews_adjusted |>
  semi_join(eligible_reviewers, by = "user_id")

# sanity checks
summary(eligible_adjusted_reviews$reviewer_mean)
mean(eligible_adjusted_reviews$normalized_mean_score)          # should be ~0
mean(eligible_adjusted_reviews$normalized_median_score == 0)   # share of exact zeros using the median
mean(eligible_adjusted_reviews$normalized_mean_score == 0)     # share of exact zeros using the mean


restaurant_summary <- st_drop_geometry(selected_points) |>
  select(business_id, business_name) |>
  left_join(all_reviewer_summary, by = "business_id") |>
  left_join(
    eligible_adjusted_reviews |>
      group_by(business_id) |>
      summarise(
        number_of_reviews_eligible_reviewers = n(),
        average_stars_eligible_reviewers     = mean(stars),
        average_normalized_score             = mean(normalized_mean_score),
        median_normalized_score              = median(normalized_mean_score),
        .groups = "drop"
      ),
    by = "business_id"
  )

# how many restaurants have enough eligible reviews to rank?
restaurant_summary |>
  summarise(
    total              = n(),
    with_5_eligible    = sum(number_of_reviews_eligible_reviewers >= 5,  na.rm = TRUE),
    with_20_eligible   = sum(number_of_reviews_eligible_reviewers >= 20, na.rm = TRUE)
  )


top10_min5 <- restaurant_summary |>
  filter(number_of_reviews_eligible_reviewers >= 5) |>
  arrange(desc(average_normalized_score)) |>
  slice_head(n = 10)

top10_min20 <- restaurant_summary |>
  filter(number_of_reviews_eligible_reviewers >= 20) |>
  arrange(desc(average_normalized_score)) |>
  slice_head(n = 10)

top10_min5  |> select(business_name, number_of_reviews_all_reviewers, average_stars_all_reviewers,
                      number_of_reviews_eligible_reviewers, average_normalized_score)
top10_min20 |> select(business_name, number_of_reviews_all_reviewers, average_stars_all_reviewers,
                      number_of_reviews_eligible_reviewers, average_normalized_score)

min_eligible <- 20

ranked <- restaurant_summary |>
  filter(number_of_reviews_eligible_reviewers >= min_eligible) |>
  mutate(
    rank_raw      = min_rank(desc(average_stars_all_reviewers)),
    rank_adjusted = min_rank(desc(average_normalized_score)),
    rank_change   = rank_raw - rank_adjusted 
  )


ranked |> arrange(desc(rank_change)) |>
  select(business_name, average_stars_all_reviewers, average_normalized_score,
         rank_raw, rank_adjusted, rank_change) |> slice_head(n = 5)

ranked |> arrange(rank_change) |>
  select(business_name, average_stars_all_reviewers, average_normalized_score,
         rank_raw, rank_adjusted, rank_change) |> slice_head(n = 5)


cor(ranked$average_stars_all_reviewers, ranked$average_normalized_score)

# scatter plot: raw vs adjusted
plot_raw_vs_adjusted <- ggplot(ranked,
                               aes(x = average_stars_all_reviewers, y = average_normalized_score)) +
  geom_hline(yintercept = 0, color = "grey70") +
  geom_point(aes(size = number_of_reviews_all_reviewers), alpha = 0.5, color = "#2c7fb8") +
  labs(title = "Raw Ratings vs. Reviewer-Adjusted Scores",
       subtitle = paste0("Restaurants with 20+ reviews from eligible reviewers (n = ", nrow(ranked), ")"),
       x = "Average stars from all reviewers",
       y = "Average normalized score\n(stars minus reviewer's usual rating)",
       size = "Reviews") +
  theme_minimal()

plot_raw_vs_adjusted
ggsave("figures/raw_vs_adjusted.png", plot_raw_vs_adjusted, width = 8, height = 6, dpi = 300, bg = "white")

saveRDS(restaurant_summary, "data/new_orleans/restaurant_summary.rds")


restaurant_areas <- readRDS("data/new_orleans/restaurant_areas.rds")

area_ratings <- function(area_col, min_restaurants = 5) {
  reviews_by_area <- category_reviews_adjusted |>
    left_join(restaurant_areas, by = "business_id")
  
  # review-level measures
  all_part <- reviews_by_area |>
    group_by(area = .data[[area_col]]) |>
    summarise(total_reviews = n(),
              average_stars_all_reviewers = mean(stars), .groups = "drop")
  
  eligible_part <- reviews_by_area |>
    semi_join(eligible_reviewers, by = "user_id") |>
    group_by(area = .data[[area_col]]) |>
    summarise(eligible_reviews = n(),
              average_normalized_score = mean(normalized_mean_score), .groups = "drop")
  
  # restaurant-level measures
  restaurant_part <- restaurant_summary |>
    left_join(restaurant_areas, by = "business_id") |>
    group_by(area = .data[[area_col]]) |>
    summarise(
      number_of_restaurants = n(),
      rankable_restaurants  = sum(number_of_reviews_eligible_reviewers >= min_eligible, na.rm = TRUE),
      pct_above_norm        = mean(average_normalized_score[
        !is.na(number_of_reviews_eligible_reviewers) &
          number_of_reviews_eligible_reviewers >= min_eligible] > 0) * 100,
      top10_restaurants     = sum(business_id %in% top10_min20$business_id),
      .groups = "drop"
    )
  
  restaurant_part |>
    left_join(all_part, by = "area") |>
    left_join(eligible_part, by = "area") |>
    filter(number_of_restaurants >= min_restaurants) |>
    mutate(rank_raw      = min_rank(desc(average_stars_all_reviewers)),
           rank_adjusted = min_rank(desc(average_normalized_score))) |>
    arrange(rank_adjusted)
}

nsa_ratings  <- area_ratings("nsa_name")
zcta_ratings <- area_ratings("zcta")

nrow(nsa_ratings)

nsa_ratings |>
  mutate(area = str_to_title(area)) |>
  select(area, number_of_restaurants, rankable_restaurants, total_reviews,
         average_stars_all_reviewers, average_normalized_score, pct_above_norm,
         top10_restaurants, rank_raw, rank_adjusted) |>
  print(n = 30, width = Inf)

zcta_ratings |>
  select(area, number_of_restaurants, average_stars_all_reviewers,
         average_normalized_score, pct_above_norm, rank_raw, rank_adjusted) |>
  print(n = 20, width = Inf)

saveRDS(nsa_ratings,  "data/new_orleans/nsa_ratings.rds")
saveRDS(zcta_ratings, "data/new_orleans/zcta_ratings.rds")

nsa_ratings |>
  filter(rankable_restaurants >= 5) |>
  mutate(area = str_to_title(area)) |>
  select(area, number_of_restaurants, rankable_restaurants, total_reviews,
         average_stars_all_reviewers, average_normalized_score, pct_above_norm,
         top10_restaurants, rank_raw, rank_adjusted) |>
  print(width = Inf)


best_nsas <- nsa_ratings |> filter(rankable_restaurants >= 5) |> pull(area)

sensitivity <- function(t) {
  elig <- reviewer_activity |> filter(reviews_in_selected_categories >= t)
  adj  <- category_reviews_adjusted |> semi_join(elig, by = "user_id")
  
  rest <- adj |>
    group_by(business_id) |>
    summarise(n_eligible = n(), score = mean(normalized_mean_score), .groups = "drop") |>
    filter(n_eligible >= min_eligible)
  
  top <- rest |> slice_max(score, n = 10)
  
  nsa_scores <- adj |>
    left_join(restaurant_areas, by = "business_id") |>
    filter(nsa_name %in% best_nsas) |>
    group_by(nsa_name) |>
    summarise(score = mean(normalized_mean_score), .groups = "drop") |>
    arrange(desc(score))
  
  tibble(
    reviewer_threshold   = t,
    reviewers_kept       = nrow(elig),
    reviews_kept         = nrow(adj),
    rankable_restaurants = nrow(rest),
    top10_same_as_main   = sum(top$business_id %in% top10_min20$business_id),
    best_nsa             = str_to_title(nsa_scores$nsa_name[1]),
    leonidas_rank        = which(nsa_scores$nsa_name == "LEONIDAS - WEST CARROLLTON"),
    french_quarter_rank  = which(nsa_scores$nsa_name == "VIEUX CARRE")
  )
}

threshold_sensitivity <- map_dfr(c(3, 5, 10), sensitivity)
threshold_sensitivity |> print(width = Inf)
write_csv(threshold_sensitivity, "figures/threshold_sensitivity.csv")

library(ggrepel)

nsa_boundaries       <- readRDS("data/new_orleans/nsa_boundaries.rds")
new_orleans_boundary <- readRDS("data/new_orleans/new_orleans_boundary.rds")

top10_points <- selected_points |>
  inner_join(top10_min20 |> select(business_id, average_normalized_score, number_of_reviews_eligible_reviewers),
             by = "business_id") |>
  arrange(desc(average_normalized_score)) |>
  mutate(rank  = row_number(),
         label = paste0(rank, ". ", business_name))

best_areas <- nsa_boundaries |>
  filter(area_name %in% c("LEONIDAS - WEST CARROLLTON", "TULANE - GRAVIER")) |>
  mutate(role = if_else(area_name == "TULANE - GRAVIER",
                        "Tulane–Gravier: high score, but driven by one restaurant",
                        "Leonidas–West Carrollton: best neighborhood overall"))

# zoom to the top 10 with some margin
box <- st_bbox(top10_points)

final_map <- ggplot() +
  geom_sf(data = nsa_boundaries, fill = "grey97", color = "grey75", linewidth = 0.2) +
  geom_sf(data = best_areas, aes(fill = role), color = "grey30", linewidth = 0.5, alpha = 0.8) +
  scale_fill_manual(values = c("#fdd49e", "#c6dbef"), name = NULL) +
  geom_sf(data = top10_points, color = "#08519c", size = 3) +
  geom_label_repel(data = top10_points,
                   aes(label = label, geometry = geometry),
                   stat = "sf_coordinates", size = 3, min.segment.length = 0,
                   box.padding = 0.4, max.overlaps = Inf) +
  coord_sf(xlim = c(box["xmin"] - 0.035, box["xmax"] + 0.02),
           ylim = c(box["ymin"] - 0.015, box["ymax"] + 0.015)) +
  labs(title = "Top 10 Seafood & Creole Restaurants in New Orleans",
       subtitle = "Ranked by reviewer-adjusted score (min. 20 reviews from reviewers with 5+ reviews)\nHighlighted: best neighborhood and the runner-up",
       caption = "Boundaries: City of New Orleans Neighborhood Statistical Areas. Data: Yelp Open Dataset.",
       x = NULL, y = NULL) +
  theme_minimal() +
  theme(legend.position = "bottom", legend.direction = "vertical")

final_map
ggsave("figures/final_top10_map.png", final_map, width = 10, height = 9, dpi = 300, bg = "white")

saveRDS(top10_points, "data/new_orleans/top10_points.rds")

leave_best_out <- category_reviews_adjusted |>
  semi_join(eligible_reviewers, by = "user_id") |>
  left_join(restaurant_areas, by = "business_id") |>
  filter(nsa_name %in% c("TULANE - GRAVIER", "LEONIDAS - WEST CARROLLTON"))

# each restaurant's contribution
leave_best_out |>
  left_join(st_drop_geometry(selected_points) |> select(business_id, business_name), by = "business_id") |>
  group_by(nsa_name, business_name) |>
  summarise(eligible_reviews = n(), score = mean(normalized_mean_score), .groups = "drop") |>
  arrange(nsa_name, desc(eligible_reviews)) |>
  print(n = 40)

# neighborhood score with and without its top-scoring rankable restaurant
top_by_area <- restaurant_summary |>
  left_join(restaurant_areas, by = "business_id") |>
  filter(nsa_name %in% c("TULANE - GRAVIER", "LEONIDAS - WEST CARROLLTON"),
         number_of_reviews_eligible_reviewers >= min_eligible) |>
  group_by(nsa_name) |>
  slice_max(average_normalized_score, n = 1)

leave_best_out |>
  group_by(nsa_name) |>
  summarise(score_all          = mean(normalized_mean_score),
            score_without_best = mean(normalized_mean_score[!business_id %in% top_by_area$business_id]),
            .groups = "drop") |>
  write_csv("figures/leave_one_out.csv")

