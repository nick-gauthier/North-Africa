---
title: "Agroecological Dynamics"
output: 
  html_document: 
    highlight: haddock
    keep_md: yes
---
Agent-based model of Roman land use and agroecology in North Africa

# Setup
Import necessary packages

```r
library(raster)  # for raster manipulation
library(MODIS) # land cover data
library(tidyverse) # for data manipulation and plotting
library(mgcv) # for fitting functions to data
library(viridis) # for color palettes
library(gridExtra) # for arranging plots
```

# Modules
First we define key functions dealing with farming, soil dynamics, and demography.

### Soil Dynamics

Define parameters controlling the soil fertility dynamics.

```r
carrying.capacity <- 100
degradation <- tibble(type = c('reversible', 'hysteresis', 'irreversible'), 
                      degradation_factor = c(0, 1, 2),
                      regeneration_rate = c(0.05, 0.0844, 0.11880))
depletion.rate <- 0.25 # .25  to represent biennial fallow, .5 otherwise
```

Soil fertility dynamics

```r
soil.dynamics <- function(x, population, soil.type = 'reversible'){
  params <- filter(degradation, type == soil.type)
  params$regeneration_rate * x * (x / carrying.capacity) ^ params$degradation_factor * (1 - x / carrying.capacity) - depletion.rate * population * 0.5 
}
```

So if you have 3 or more households per sq km (or 6 or more households practicing biennial fallow) then the soil will always deplete.
![](agroecology_files/figure-html/unnamed-chunk-1-1.png)<!-- -->

### Farming
Agents determine how much land they need, calculate the yields from their land, remember these yields, and harvest from the land.

First define some parameters relating to food production and consumption.

```r
max.yield <- 1500 # maximum possible wheat yield, in kg/ha, should range from 1000 - 2000

calorie.req <- 2582 * 365  # annual individual calorie requirement, derived from daily requirement
wheat.calories <- 3320 # calories in a kg of wheat
wheat.cal.proportion <- 0.75 # percent of individual's food calories coming from wheat
wheat.req <- calorie.req / wheat.calories * wheat.cal.proportion # kg of wheat to feed a person for 1 year

sowing_rate <- 135  # kg of wheat to sow a hectare (range 108 - 135 from Roman agronomists)
seed_proportion <- 135 / max.yield # proportion of harvest to save as seed for next year's sowing

labor.per.hectare <- 40 # person days per hectare
max.ag.labor <- 300 # maximum days per year an individual can devote to farming
max.memory <- 15 # maximum number of years a household remembers
production_elasticity <- 0.2
```

Crop yields are determined by rainfall and soil fertility.

```r
yield <- function(fertility, precipitation){
  f.reduction <- pmax(0, 0.19 * log(fertility / 100) + 1)  # fertility impact on yields
  p.reduction <- pmax(0, 0.51 * log(precipitation) + 1.03)  # annual precipitation impact on yields
  return(max.yield * f.reduction  * p.reduction)
} 
#todo, replace with gams!
```


![](agroecology_files/figure-html/unnamed-chunk-2-1.png)<!-- -->

How agents decide the amount of land they need to farm. The determination of how much land is needed is a function of the household's occupants and labor availability.

```r
land.req <- function(population, yield, laborers, fallow = T){
  land <- wheat.req * population * (1 + seed_proportion) / yield * ifelse(fallow, 2, 1)
  pmin(land, max.ag.labor * laborers * ifelse(fallow, 2, 1) / labor.per.hectare) # constrain by maximum hectares per household 
}
```

![](agroecology_files/figure-html/unnamed-chunk-3-1.png)<!-- -->

Here households calculate how much land they need, pull the crop yield from the environment, remember the yield, and determine their harvests by multiplying the yield by the amount of land they have (also removing some of the crop to save as seed for next year).

first, for dev purposes, make a fake environment raster.

```r
allocate_land <- function(households){
  households %>% 
   mutate(land_req = land.req(n_inhabitants, peak_end(yield_memory), laborers),
          total_land_req = sum(land_req),
          land = if_else(total_land_req < (arable_proportion * 100), land_req, land_req / total_land_req * arable_proportion * 100)) %>%
    select(-land_req, -total_land_req)
}
```


```r
farm <- function(households){
  households %>%
    mutate(yield = yield(soil_fertility, precip) * 0.5,
           yield_memory = map2(.data$yield_memory, .data$yield, remember),
           harvest = land * this.yield - land * sowing_rate,
           soil_fertility = soil_fertility + soil.dynamics(soil_fertility, laborers, 'reversible'))
}
```


```r
remember <- function(yield_memory, yield){
  yield_memory <- rnorm(1, yield, yield * 0.0333) %>%  #memory is fuzzy
    c(yield_memory)
  if(length(yield_memory) > max.memory) yield_memory <- yield_memory[1:max.memory]
  return(yield_memory)
}
```

Agents use the peak-end rule when accessing memory.

```r
peak_end <- function(x){
  map_dbl(x, ~mean(c(.x[1], min(.x))))
}
```


```r
random.series <- rnorm(100, mean = 200, sd = 50)
mem <- c()
for(i in 1:100){
  mem <- c(mem, mean(c(random.series[i], min(random.series[i:(min(i+14, 100))]))))  
}
qplot(x = 1:100, y = rev(random.series), geom = 'line') +
  geom_line(aes(y = rev(mem)), color = 'red', linetype = 2) +
  labs(x = 'Year', y = 'Crop Yield', title = 'Impact of peak-end rule on yield memory', subtitle = 'Randomly generated crop yields (black) and resulting "memory" (red), given a 15 year memory length') +
  theme_minimal()
```

![](agroecology_files/figure-html/unnamed-chunk-6-1.png)<!-- -->

Finally eat the harvested food, updating storage and food_ratio accordingly

```r
eat <- function(households){
  households %>%
    mutate(total.cal.req = n_inhabitants * wheat.req,
           food_ratio = (storage + harvest) / total.cal.req,
           old.storage = storage,
           storage = if_else(total.cal.req <= storage, harvest, pmax(harvest - (total.cal.req - old.storage), 0))) %>%
    select(-old.storage, -total.cal.req, -harvest)
}
```

### Demography

Generate fertility and mortality tables from pre-prepared data.

```r
fertility_table <- tibble(
  age = 10:49,
  rate = rep(c(0.022, 0.232, 0.343, 0.367, 0.293, 0.218, 0.216, 0.134), each = 5)
)
mortality_table <- tibble(
  age = c(0:84),
  rate = c(0.4669, rep(0.0702, 4), rep(c(0.0132, 0.0099, 0.0154, 0.0172, 0.0195, 0.0223, 0.0259, 0.0306, 0.0373, 0.0473, 0.0573, 0.0784, 0.1042, 0.1434, 0.2039, 0.2654), each = 5))
)
```

![](agroecology_files/figure-html/unnamed-chunk-8-1.png)<!-- -->

Calculate functions for vital rate elasticities from pre-prepared data.

```r
fertility_elasticity <- read_csv('data/fertility_data.csv', skip = 1) %>% 
  rename(food_ratio = X, fertility_reduction = Y) %>%
  gam(fertility_reduction ~ s(food_ratio), dat = .)
mort_elast <- read_csv('data/mortality_dataset.csv', skip = 1)

survivorship_elasticity <- bind_rows(
    mort_elast[1:2] %>% mutate(age = 1) %>% rename(food_ratio = X, mortality_reduction = Y), 
    mort_elast[3:4] %>% mutate(age = 25) %>% rename(food_ratio = X_1, mortality_reduction = Y_1),
    mort_elast[5:6] %>% mutate(age = 5) %>% rename(food_ratio = X_2, mortality_reduction = Y_2),
    mort_elast[7:8] %>% mutate(age = 65) %>% rename(food_ratio = X_3, mortality_reduction = Y_3)
  ) %>%
  group_by(age) %>%
  nest %>% 
  mutate(model = map(data, ~gam(mortality_reduction ~ s(food_ratio), dat = .))) %>%
  select(-data) %>%
  arrange(age) %>%
  slice(c(rep(1, 5), rep(2, 20), rep(3, 40), rep(4, 20))) %>%
  mutate(age = 0:84)
```

Birth

```r
reproduce <- function(inhabitants, food_ratio){
  fertility_reduction <- ifelse(food_ratio >= 1, 1, predict(fertility_elasticity, list(food_ratio = food_ratio)))
  
  babies <- inhabitants %>%
    filter(age >= 12 & age < 50) %>% # only individuals of child bearing age reproduce
    inner_join(fertility_table, by = 'age') %>%  # find the fertility rate corresponding to the individual's age
    mutate(baby = (rate / 2 * fertility_reduction) > runif(n())) %>%  # divide by two to make everyone female ...
    .$baby %>% # select just the babies column
    sum  # add it up to determine the number of newborns in the house
  
  if(babies > 0) inhabitants <- add_row(inhabitants, age = rep(0, babies))
  return(inhabitants)
}
```

Death

```r
die <- function(inhabitants, food_ratio){
  inhabitants %>%
    inner_join(mortality_table, by = 'age') %>%
    inner_join(survivorship_elasticity, by = 'age') %>%
    mutate(survivorship_reduction = ifelse(food_ratio >= 1, 1, map_dbl(model, ~predict(.x, list(food_ratio = food_ratio)))),
           dead = ((1 - rate) * survivorship_reduction) < runif(n())) %>%
    filter(dead == F) %>%
    select(age)
}
```

Agents first reproduce, then die, then age, and finally remove households with no inhabiants.

```r
birth_death <- function(households){
  households %>%
    mutate(inhabitants = map2(inhabitants, food_ratio, reproduce),
           inhabitants = map2(inhabitants, food_ratio, die),
           inhabitants = map(inhabitants, ~mutate(.x, age = age + 1)),
           n_inhabitants = map_int(inhabitants, nrow),
           laborers = map_dbl(inhabitants, ~filter(.x, age >= 20 & age < 45) %>% nrow)) %>%
    filter(n_inhabitants > 0)
}
```

If households get larger than 10 inhabitants, they split into two.

```r
fission <- function(households){
  static.households <- households %>% 
    filter(n_inhabitants < 10)
  
  if(nrow(static.households) == nrow(households)){
    return(households)
  } else{
  tmp <- households %>%
    filter(n_inhabitants >= 10) %>% 
    mutate(indices = map(inhabitants, ~sample.int(nrow(.x), nrow(.x) * 0.5)))
  
  old <- tmp %>% mutate(storage = .5 * storage,
                       land = .5 * land,
                       inhabitants = map2(inhabitants, indices, ~slice(.x, .y)),
                       n_inhabitants = map_int(inhabitants, nrow))
  
  new <- tmp %>% mutate(storage = .5 * storage,
                land = .5 * land,
                inhabitants = map2(inhabitants, test, ~slice(.x, -.y)),
                n_inhabitants = map_int(inhabitants, nrow))
  
  return(bind_rows(static.households, old, new) %>%
    mutate(n_inhabitants = map_int(inhabitants, nrow),
           laborers = map_dbl(inhabitants, ~filter(.x, age >= 20 & age < 45) %>% nrow)))
  }
}
```


# Simulation
Start with the populaiton level parameters, i.e. how many settlements, households, and individuals to start the simulation with.


```r
init_settlements <- 1 
init_households <- 2
init_inhabitants <- 3
init_age <- 25
```

Create a 2 villages of 10 households with 6 people in each.

```r
create.households <- function(x){
  tibble(household = 1:x,
         n_inhabitants = init_inhabitants,
         storage = n_inhabitants * wheat.req,
         yield_memory = c(max.yield),
         food_ratio = 1) %>%
    mutate(inhabitants = map(n_inhabitants, create.inhabitants),
           laborers = map_dbl(inhabitants, ~filter(.x, age >= 20 & age < 45) %>% nrow)) %>%
    mutate(soil_fertility = 100)
}

create.inhabitants <- function(x){
  tibble(age = rep(init_age, x))
}

population <- tibble(settlement = 1:init_settlements,
                     households = init_households) %>%
              mutate(households = map(households, create.households))
```

Test environment, generate simple raster to represent our environment

```r
arable_proportion <- 0.9
sim.out <- tibble(year = 0, population = 0, fertility =  0, replicate = 0)
nsim <- 100
replicates <- 10
precip <- 1
pb <- txtProgressBar(min = 0, max = replicates, style = 3)

for(j in 1:replicates){
test <- population$households[[1]]
for(i in 1:nsim){
  #this.yield <- overlay(soil, precip, fun = yield) %>% getValues() * 0.5 # *.5 for fallow
test <- test %>% 
  allocate_land %>%
  farm %>%
  eat %>%
  birth_death %>%
  fission

sim.out <- add_row(sim.out, year = i, population = sum(test$n_inhabitants), fertility = mean(test$soil_fertility), replicate = j)
}
setTxtProgressBar(pb, j)

}
close(pb)
sim.out <- sim.out[-1,]


ggplot(sim.out, aes(year, population, group = replicate)) +
  geom_line(alpha = .2) +
  theme_minimal()

ggplot(sim.out, aes(year, fertility, group = replicate)) +
  geom_line(alpha = .2) +
  theme_minimal()
```

# Environment

## Input data

Set a bounding box for the study area.

```r
bbox <- extent(5, 11.5, 34, 37.5)
```

Import SRTM GDEM data for the elevation basemap.

```r
elevation <- raster('~/gdrive/Data/SRTM_1km.tif') %>% crop(bbox)
elev_dat <- as.data.frame(elevation, xy =  T, na.rm = T) %>%
  rename(elevation = SRTM_1km)
```



Calculate slope in degrees from the SRTM elevation.

```r
slope <- terrain(elevation, opt = 'slope', unit = 'degrees')
slope_dat <- as.data.frame(slope, xy = T, na.rm = T)
```




```r
grid.arrange(p1, p2, ncol = 2)
```

![](agroecology_files/figure-html/unnamed-chunk-14-1.png)<!-- -->


Where is arable land? Calculate the frequency of land with < 5 degree slope within 2.5 km.

```r
focalWeight(slope < 5, 0.008333333 * 2, type = 'circle') %>%
  focal(slope < 5, ., sum) %>%
  as.data.frame(xy = T, na.rm = T) %>%
  ggplot(aes(x, y)) +
  geom_raster(aes(fill = layer)) +
  scale_fill_viridis(name = 'Proportion \narable land') +
  theme_void() +
  coord_quickmap() +
  labs(title = 'Arable land')
```

![](agroecology_files/figure-html/arable_land-1.png)<!-- -->

Now import temperature and precipitation data.

```r
prec <- brick('data/CHELSA/prec_1km.tif') %>% sum
gdd5 <- raster('data/CHELSA/gdd5_1km.tif')

prec_dat <- as.data.frame(prec, xy = T, na.rm = T)
gdd5_dat <- as.data.frame(gdd5, xy = T, na.rm = T)
```

![](agroecology_files/figure-html/unnamed-chunk-15-1.png)<!-- -->
Soils

```r
soils <- merge(raster('data/soils/TAXNWRB_1km_Tunisia.tiff') %>% crop(bbox),
               raster('data/soils/TAXNWRB_1km_Algeria.tiff') %>% crop(bbox), tolerance = .3)
soils_dat <- as.data.frame(soils, xy =  T, na.rm = T) %>%
  rename(type = layer) %>%
  mutate(type = as.factor(type))
```

![](agroecology_files/figure-html/unnamed-chunk-17-1.png)<!-- -->


Vegetation

```r
pft <- raster('data/MODIS/MCD12Q1.051_20170918110118/MCD12Q1.A2001001.Land_Cover_Type_5.tif') %>%
  projectRaster(disaggregate(elevation, 2), method = 'ngb') %>%
  as.data.frame(xy = T, na.rm = T) %>%
    rename(pft = MCD12Q1.A2001001.Land_Cover_Type_5) %>%
  #filter(!pft %in% c(0, 7:10)) %>%
  mutate(pft = recode_factor(as.factor(pft),
                               `0` = 'Water',
                               `1` = 'Evergreen Needleleaf trees',
                               `2` = 'Evergreen Broadleaf trees',
                               `3` = 'Deciduous Needleleaf trees',
                               `4` = 'Deciduous Broadleaf trees',
                               `5` = 'Shrub',
                               `6` = 'Grass',
                               `7` = 'Cereal crops',
                               `8` = 'Broad-leaf crops',
                               `9` = 'Urban and built-up',
                               `10` =	'Snow and ice',
                               `11` = 'Barren or sparse vegetation'))
```

![](agroecology_files/figure-html/unnamed-chunk-18-1.png)<!-- -->

Let's put all these environmental rasters together in a single brick for easier access.

```r
environment <- brick(slope, prec, gdd5)
```

