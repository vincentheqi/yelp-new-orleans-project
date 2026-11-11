library(tidyverse)
library(sf)
library(tigris)
options(tigris_use_cache = TRUE)

new_orleans_restaurants <- readRDS("data/new_orleans/business_new_orleans.rds")
selected_restaurants    <- readRDS("data/new_orleans/selected_restaurants.rds")


louisiana_places <- places(state = "LA", cb = TRUE, year = 2024, class = "sf") |>
  st_transform(4326)         


restaurant_points <- new_orleans_restaurants |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)


restaurants_with_place <- restaurant_points |>
  st_join(louisiana_places |> select(GEOID, place_name = NAME),
          join = st_within, left = TRUE)

restaurants_with_place |>
  st_drop_geometry() |>
  count(city, place_name, sort = TRUE)

# look at the restaurants outside the official boundary
restaurants_with_place |>
  st_drop_geometry() |>
  filter(place_name != "New Orleans") |>
  select(business_name, address, postal_code, place_name) |>
  arrange(place_name) |>
  print(n = 20)


new_orleans_boundary <- louisiana_places |> filter(NAME == "New Orleans")

selected_points <- restaurants_with_place |>
  filter(place_name == "New Orleans") |>
  semi_join(selected_restaurants, by = "business_id")

nrow(selected_points)


dir.create("figures", showWarnings = FALSE)

map_boundary <- ggplot() +
  geom_sf(data = new_orleans_boundary, fill = "grey95", color = "grey35") +
  geom_sf(data = selected_points, aes(color = stars), alpha = 0.7, size = 1.5) +
  scale_color_viridis_c(option = "C", limits = c(1, 5)) +
  labs(title = "Seafood & Creole Restaurants in New Orleans",
       subtitle = "Yelp restaurants inside the official Census city boundary",
       color = "Yelp\nstars") +
  theme_minimal()

map_boundary
ggsave("figures/map_boundary_selected.png", map_boundary, width = 8, height = 6, dpi = 300)

saveRDS(selected_points, "data/new_orleans/selected_points.rds")


# 1. ZIP Code Tabulation Areas: New Orleans ZIPs all start with 701
zctas_la <- zctas(year = 2020, cb = TRUE, starts_with = "701", class = "sf") |>
  st_transform(4326) |>
  select(area_id = ZCTA5CE20) |>
  mutate(area_name = area_id)

# 2. Census tracts for Orleans Parish
tracts_nola <- tracts(state = "LA", county = "Orleans", year = 2024, cb = TRUE, class = "sf") |>
  st_transform(4326) |>
  select(area_id = GEOID, area_name = NAMELSAD)

# 3. Neighborhood Statistical Areas from the City of New Orleans GIS server
nsa_url <- paste0(
  "https://gis.nola.gov/arcgis/rest/services/apps/BoundariesMayorysViewer/",
  "MapServer/3/query?where=1%3D1&outFields=*&outSR=4326&f=geojson"
)
nsa_nola <- st_read(nsa_url, quiet = TRUE) |>
  st_make_valid() |>
  select(area_name = LUP_LAB) |>
  mutate(area_id = area_name)

nrow(zctas_la)
nrow(tracts_nola)
nrow(nsa_nola)
head(nsa_nola$area_name, 10)

category_reviews <- readRDS("data/new_orleans/category_reviews.rds")

# number of reviews for each restaurant, counted from our own review table (not Yelp's review_count)
review_totals <- category_reviews |>
  count(business_id, name = "number_of_reviews")

selected_points <- selected_points |>
  left_join(review_totals, by = "business_id")

compare_geography <- function(points, areas, system_name) {
  
  joined <- points |>
    st_join(areas, join = st_within, left = TRUE)
  
  by_area <- joined |>
    st_drop_geometry() |>
    filter(!is.na(area_id)) |>
    group_by(area_id, area_name) |>
    summarise(
      number_of_restaurants  = n(),
      average_business_stars = mean(stars, na.rm = TRUE),
      median_business_stars  = median(stars, na.rm = TRUE),
      total_reviews          = sum(number_of_reviews, na.rm = TRUE),
      .groups = "drop"
    ) |>
    arrange(desc(number_of_restaurants))
  
  # areas whose interior point falls inside the official city boundary
  areas_in_city <- areas |>
    st_point_on_surface() |>
    st_filter(new_orleans_boundary) |>
    nrow()
  
  summary_row <- tibble(
    geographic_system      = system_name,
    number_of_areas        = areas_in_city,
    areas_with_restaurants = nrow(by_area),
    restaurants_assigned   = sum(!is.na(joined$area_id)),
    unmatched_restaurants  = sum(is.na(joined$area_id)),
    extra_matches          = nrow(joined) - nrow(points),   # >0 means a point matched 2 polygons
    smallest_area_count    = min(by_area$number_of_restaurants),
    largest_area_count     = max(by_area$number_of_restaurants),
    median_area_count      = median(by_area$number_of_restaurants),
    areas_with_5_or_more   = sum(by_area$number_of_restaurants >= 5)
  )
  
  list(joined = joined, by_area = by_area, summary = summary_row)
}

zcta_result  <- compare_geography(selected_points, zctas_la,   "ZIP/ZCTA")
tract_result <- compare_geography(selected_points, tracts_nola, "Census tract")
nsa_result   <- compare_geography(selected_points, nsa_nola,   "Neighborhood Statistical Area")

geography_comparison <- bind_rows(zcta_result$summary,
                                  tract_result$summary,
                                  nsa_result$summary)

geography_comparison |> print(width = Inf)


# map restaurant counts for one geographic system
map_counts <- function(areas, result, title) {
  map_data <- areas |>
    st_intersection(st_geometry(new_orleans_boundary)) |>     # clip to the city
    left_join(result$by_area |> select(area_id, number_of_restaurants), by = "area_id")
  
  ggplot(map_data) +
    geom_sf(aes(fill = number_of_restaurants), color = "white", linewidth = 0.2) +
    scale_fill_viridis_c(option = "mako", direction = -1, na.value = "grey90",
                         trans = "log10", breaks = c(1, 5, 20, 50, 150),
                         name = "Restaurants\n(log scale)") +
    labs(title = title, caption = "Grey = no seafood/Creole restaurants") +
    theme_void()
}

map_zcta  <- map_counts(zctas_la,   zcta_result,  "Restaurants per ZIP code (ZCTA)")
map_tract <- map_counts(tracts_nola, tract_result, "Restaurants per census tract")
map_nsa   <- map_counts(nsa_nola,   nsa_result,   "Restaurants per Neighborhood Statistical Area")

map_zcta; map_tract; map_nsa

ggsave("figures/map_counts_zcta.png",  map_zcta,  width = 7, height = 6, dpi = 300, bg = "white")
ggsave("figures/map_counts_tract.png", map_tract, width = 7, height = 6, dpi = 300, bg = "white")
ggsave("figures/map_counts_nsa.png",   map_nsa,   width = 7, height = 6, dpi = 300, bg = "white")

# top neighborhoods by number of restaurants
nsa_result$by_area |>
  mutate(area_name = str_to_title(area_name)) |>
  slice_head(n = 10) |>
  print(width = Inf)

write_csv(geography_comparison, "figures/geography_comparison.csv")


# save area assignments and boundaries for later scripts and the report
nsa_result$joined |>
  st_drop_geometry() |>
  select(business_id, nsa_name = area_name) |>
  left_join(zcta_result$joined |> st_drop_geometry() |> select(business_id, zcta = area_id),
            by = "business_id") |>
  saveRDS("data/new_orleans/restaurant_areas.rds")

saveRDS(nsa_nola,             "data/new_orleans/nsa_boundaries.rds")
saveRDS(zctas_la,             "data/new_orleans/zcta_boundaries.rds")
saveRDS(new_orleans_boundary, "data/new_orleans/new_orleans_boundary.rds")

