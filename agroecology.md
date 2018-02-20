---
title: "Agroecology_dyn"
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
```

```
## Loading required package: sp
```

```r
library(MODIS)
```

```
## Loading required package: mapdata
```

```
## Loading required package: maps
```

```r
library(tidyverse) # for data manipulation and plotting
```

```
## ── Attaching packages ──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────── tidyverse 1.2.1 ──
```

```
## ✔ ggplot2 2.2.1     ✔ purrr   0.2.4
## ✔ tibble  1.4.2     ✔ dplyr   0.7.4
## ✔ tidyr   0.8.0     ✔ stringr 1.2.0
## ✔ readr   1.1.1     ✔ forcats 0.2.0
```

```
## ── Conflicts ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────── tidyverse_conflicts() ──
## ✖ tidyr::extract() masks raster::extract()
## ✖ dplyr::filter()  masks stats::filter()
## ✖ dplyr::lag()     masks stats::lag()
## ✖ purrr::map()     masks maps::map()
## ✖ dplyr::select()  masks raster::select()
```

```r
library(mgcv) # for fitting functions to data
```

```
## Loading required package: nlme
```

```
## 
## Attaching package: 'nlme'
```

```
## The following object is masked from 'package:dplyr':
## 
##     collapse
```

```
## The following object is masked from 'package:raster':
## 
##     getData
```

```
## This is mgcv 1.8-23. For overview type 'help("mgcv-package")'.
```

```r
library(viridis) # for color palettes
```

```
## Loading required package: viridisLite
```

# Environment
Set a bounding box for the study area.

```r
bbox <- extent(5, 11.5, 34, 37.5)
```

Import SRTM GDEM data for the elevation basemap.

```r
elev <- raster('~/gdrive/Data/SRTM_1km.tif') %>% crop(bbox)
elev_dat <- as.data.frame(elev, xy =  T, na.rm = T) %>%
  rename(elev = SRTM_1km)

ggplot(elev_dat, aes(x, y)) +
  geom_raster(aes(fill = elev)) +
  scale_fill_gradientn(colours = terrain.colors(10), name = 'Meters') +
  theme_void() +
  coord_quickmap() +
  labs(title = 'Elevation', subtitle = 'Africa Proconsularis')
```

![](agroecology_files/figure-html/elevation-1.png)<!-- -->

Calculate slope in degrees from the SRTM elevation.

```r
slope <- terrain(elev, opt = 'slope', unit = 'degrees')
slope_dat <- as.data.frame(slope, xy = T, na.rm = T)

ggplot(slope_dat, aes(x, y)) +
  geom_raster(aes(fill = slope)) +
  scale_fill_viridis(name = 'Degrees', option = 'B') +
  theme_void() +
  coord_quickmap() +
  labs(title = 'Slope', subtitle = 'Africa Proconsularis')
```

![](agroecology_files/figure-html/slope-1.png)<!-- -->

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
  labs(title = 'Arable land', subtitle = 'Africa Proconsularis')
```

![](agroecology_files/figure-html/arable_land-1.png)<!-- -->

Now import temperature and precipitaiton data.

```r
prec <- brick('data/CHELSA/prec_1km.tif') %>% sum
gdd5 <- raster('data/CHELSA/gdd5_1km.tif')
rasterVis::levelplot(prec)
```

![](agroecology_files/figure-html/climate-1.png)<!-- -->

```r
rasterVis::levelplot(gdd5)
```

![](agroecology_files/figure-html/climate-2.png)<!-- -->

Vegetation

```r
pft <- raster('data/MODIS/MCD12Q1.051_20170918110118/MCD12Q1.A2001001.Land_Cover_Type_5.tif') %>%
  projectRaster(disaggregate(elev, 2), method = 'ngb')


  test <- pft %>%
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

lc_colors <- c('#000080', '#008000', '#00FF00', '#99CC00', '#99FF99', '#FFCC99', '#FF9900', '#FFFF00', '#999966', '#FF0000', '#FFFFFF', '#808080') 
               #'#016400', '#018200', '#97bf47','#dcce00',  '#fffbc3')
# colors inspired by https://lpdaac.usgs.gov/about/news_archive/modisterra_land_cover_types_yearly_l3_global_005deg_cmg_mod12c1
ggplot(test, aes(x, y)) + 
  geom_tile(aes(fill = pft)) + 
  scale_fill_manual(values = lc_colors) + 
  theme_void() +
  coord_quickmap() +
  labs(title = 'Vegetation distribution', subtitle = 'Africa Proconsularis, present day')
```

![](agroecology_files/figure-html/vegetation-1.png)<!-- -->

# Social Model
Now move onto the social model.
## Parameters
First we need to define all the neccessary parameters.
Start with the populaiton level parameters, i.e. how many settlements, households, and individuals to start the simulation with.


```r
init_settlements <- 1 
init_households <- 3
init_inhabitants <- 6
init_age <- 25
```

Then define some parameters relating to food production and consumption.

```r
calorie.req <- 212  # kg of wheat to feed a person for 1 year, assuming grain is 75% of diet
#sowing_rate <- 135  #108 # kg of wheat to sow a hectare
kg.to.calories <- 3320 # kcals in one kg of wheat
labor.per.hectare <- 40 # person days per hectare
max.ag.labor <- 300 # maximum days per year an individual can devote to farming
max.yield <- 2000
max.memory <- 15 # maximum number of years a household remembers
production_elasticity <- 0.2
```

Finally define parameters controlling the soil fertility dynamics.

```r
carrying.capacity <- 100
degredation.factor <- 0 # c(2, 1, 0)
regeneration.rate <- 0.05 # c(0.1188, 0.0844, 0.05)
depletion.rate <- 0.5
```

Now we move onto defining key functions dealing with farming, soil dynamics, and demography.

## Modules
### Farming

How agents decide the amount of land they need to farm.


Agents determine how much land they need, calculate the yields from their  land, remember these yields, and harvest from the land

```r
farm <- function(households){
  households %>%
    mutate(land = land.req(n_inhabitants, peak_end(yield_memory), laborers),
           yield = this.yield,
           yield_memory = map2(.data$yield_memory, .data$yield, remember),
           harvest = land * this.yield) #%>%
    #select(-land, -yield)
}

remember <- function(yield_memory, yield){
  yield_memory <- c(yield, yield_memory)
  if(length(yield_memory) > max.memory) yield_memory <- yield_memory[1:15]
  return(yield_memory)
}
```

The determination of how much land is needed is a function of the household's occupants and labor availability.

```r
land.req <- function(population, yield, laborers){
  land <- calorie.req * population * (1 + 0) / yield
  pmin(land, max.ag.labor * laborers / labor.per.hectare) # constrain by maximum hectares per household 
}
```

Agents use the peak-end rule when accessing memory.

```r
peak_end <- function(x){
  map_dbl(x, ~mean(c(.x[1], min(.x))))
}
```

Finally eat the harvested food, updating storage and food_ratio accordingly

```r
eat <- function(households){
  households %>%
    mutate(total.cal.req = n_inhabitants * calorie.req,
           food_ratio = (storage + harvest) / total.cal.req,
           old.storage = storage,
           storage = if_else(total.cal.req <= storage, harvest, pmax(harvest - (total.cal.req - old.storage), 0))) %>%
    select(-old.storage, -total.cal.req, -harvest)
}
```


### Soil Dynamics

Crop yields determined by rainfall and soil fertility.

```r
yield <- function(fertility, precipitation){
  f.reduction <- pmax(0, 0.19 * log(fertility / 100) + 1)  # fertility impact on yields
  p.reduction <- pmax(0, 0.51 * log(precipitation) + 1.03)  # annual precipitation impact on yields
  return(max.yield * f.reduction  * p.reduction)
} 
#todo, replace with gams!
```

Soil fertility dynamics

```r
soil.dynamics <- function(x, population){
  newsoil <- x + regeneration.rate * x * (x / carrying.capacity) ^ degredation.factor * (1 - x / carrying.capacity) - depletion.rate * population
  return(max(newsoil, 0))
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

ggplot(mortality_table, aes(age, rate)) +
  geom_line(color = 'red') +
  geom_line(data = fertility_table, color = 'blue') +
  labs(title = 'Fertility and Mortality Rates', subtitle = 'Per capita fertility (blue) and mortality (red) in the Roman Empire', x = 'Age', y = 'Vital rate') +
  theme_bw()
```

![](agroecology_files/figure-html/birth-death-1.png)<!-- -->

Calculate functions for vital rate elasticities from pre-prepared data.

```r
fertility_elasticity <- read_csv('data/fertility_data.csv', skip = 1) %>% 
  rename(food_ratio = X, fertility_reduction = Y) %>%
  gam(fertility_reduction ~ s(food_ratio), dat = .)
```

```
## Parsed with column specification:
## cols(
##   X = col_double(),
##   Y = col_double()
## )
```

```r
mort_elast <- read_csv('data/mortality_dataset.csv', skip = 1)
```

```
## Warning: Duplicated column names deduplicated: 'X' => 'X_1' [3], 'Y' =>
## 'Y_1' [4], 'X' => 'X_2' [5], 'Y' => 'Y_2' [6], 'X' => 'X_3' [7], 'Y' =>
## 'Y_3' [8]
```

```
## Parsed with column specification:
## cols(
##   X = col_double(),
##   Y = col_double(),
##   X_1 = col_double(),
##   Y_1 = col_double(),
##   X_2 = col_double(),
##   Y_2 = col_double(),
##   X_3 = col_double(),
##   Y_3 = col_double()
## )
```

```r
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

plot(fertility_elasticity)
```

![](agroecology_files/figure-html/vital-rate-elasticity-1.png)<!-- -->

Birth

```r
reproduce <- function(inhabitants, food_ratio){
  fertility_reduction <- ifelse(food_ratio >= 1, 1, predict(fertility_elasticity, list(food_ratio = food_ratio)))
  
  babies <- inhabitants %>%
    filter(age >= 12 & age < 50) %>%   # only individuals of child bearing age reproduce
    inner_join(fertility_table, by = 'age') %>%    # find the fertility rate corresponding to the individual's age
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


# Simulation runs
Create a 2 villages of 10 households with 6 people in each.

```r
create.households <- function(x){
  tibble(household = 1:x,
         n_inhabitants = init_inhabitants,
         storage = n_inhabitants * calorie.req,
         yield_memory = c(max.yield),
         food_ratio = 1) %>%
    mutate(inhabitants = map(n_inhabitants, create.inhabitants),
           laborers = map_dbl(inhabitants, ~filter(.x, age >= 20 & age < 45) %>% nrow))
}

create.inhabitants <- function(x){
  tibble(age = rep(25, x))
}

population <- tibble(settlement = 1:init_settlements,
                     households = init_households) %>%
              mutate(households = map(households, create.households))
```

Test environment, generate simple raster to represent our environment

```r
precip <- raster(nrow = 1, ncol = 1) %>% setValues(1)
soil <- raster(nrow = 1, ncol = 1) %>% setValues(100)
test <- population$households[[1]]
out <- c()
nsim <- 500
pb <- txtProgressBar(min = 0, max = nsim, style = 3)
```

```
##   |                                                                         |                                                                 |   0%
```

```r
for(i in 1:nsim){
  this.yield <- overlay(soil, precip, fun = yield) %>% getValues()
test <- test%>% 
  farm %>%
  eat %>%
  birth_death

soil <- soil.dynamics(soil, nrow(test))
out <- c(out, sum(test$n_inhabitants))
setTxtProgressBar(pb, i)
}
```

```
##   |                                                                         |                                                                 |   1%  |                                                                         |=                                                                |   1%  |                                                                         |=                                                                |   2%  |                                                                         |==                                                               |   2%  |                                                                         |==                                                               |   3%  |                                                                         |==                                                               |   4%  |                                                                         |===                                                              |   4%  |                                                                         |===                                                              |   5%  |                                                                         |====                                                             |   5%  |                                                                         |====                                                             |   6%  |                                                                         |====                                                             |   7%  |                                                                         |=====                                                            |   7%  |                                                                         |=====                                                            |   8%  |                                                                         |======                                                           |   9%  |                                                                         |======                                                           |  10%  |                                                                         |=======                                                          |  10%  |                                                                         |=======                                                          |  11%  |                                                                         |========                                                         |  12%  |                                                                         |========                                                         |  13%  |                                                                         |=========                                                        |  13%  |                                                                         |=========                                                        |  14%  |                                                                         |=========                                                        |  15%  |                                                                         |==========                                                       |  15%  |                                                                         |==========                                                       |  16%  |                                                                         |===========                                                      |  16%  |                                                                         |===========                                                      |  17%  |                                                                         |===========                                                      |  18%  |                                                                         |============                                                     |  18%  |                                                                         |============                                                     |  19%  |                                                                         |=============                                                    |  19%  |                                                                         |=============                                                    |  20%  |                                                                         |=============                                                    |  21%  |                                                                         |==============                                                   |  21%  |                                                                         |==============                                                   |  22%  |                                                                         |===============                                                  |  22%  |                                                                         |===============                                                  |  23%  |                                                                         |===============                                                  |  24%  |                                                                         |================                                                 |  24%  |                                                                         |================                                                 |  25%  |                                                                         |=================                                                |  25%  |                                                                         |=================                                                |  26%  |                                                                         |=================                                                |  27%  |                                                                         |==================                                               |  27%  |                                                                         |==================                                               |  28%  |                                                                         |===================                                              |  29%  |                                                                         |===================                                              |  30%  |                                                                         |====================                                             |  30%  |                                                                         |====================                                             |  31%  |                                                                         |=====================                                            |  32%  |                                                                         |=====================                                            |  33%  |                                                                         |======================                                           |  33%  |                                                                         |======================                                           |  34%  |                                                                         |======================                                           |  35%  |                                                                         |=======================                                          |  35%  |                                                                         |=======================                                          |  36%  |                                                                         |========================                                         |  36%  |                                                                         |========================                                         |  37%  |                                                                         |========================                                         |  38%  |                                                                         |=========================                                        |  38%  |                                                                         |=========================                                        |  39%  |                                                                         |==========================                                       |  39%  |                                                                         |==========================                                       |  40%  |                                                                         |==========================                                       |  41%  |                                                                         |===========================                                      |  41%  |                                                                         |===========================                                      |  42%  |                                                                         |============================                                     |  42%  |                                                                         |============================                                     |  43%  |                                                                         |============================                                     |  44%  |                                                                         |=============================                                    |  44%  |                                                                         |=============================                                    |  45%  |                                                                         |==============================                                   |  45%  |                                                                         |==============================                                   |  46%  |                                                                         |==============================                                   |  47%  |                                                                         |===============================                                  |  47%  |                                                                         |===============================                                  |  48%  |                                                                         |================================                                 |  49%  |                                                                         |================================                                 |  50%  |                                                                         |=================================                                |  50%  |                                                                         |=================================                                |  51%  |                                                                         |==================================                               |  52%  |                                                                         |==================================                               |  53%  |                                                                         |===================================                              |  53%  |                                                                         |===================================                              |  54%  |                                                                         |===================================                              |  55%  |                                                                         |====================================                             |  55%  |                                                                         |====================================                             |  56%  |                                                                         |=====================================                            |  56%  |                                                                         |=====================================                            |  57%  |                                                                         |=====================================                            |  58%  |                                                                         |======================================                           |  58%  |                                                                         |======================================                           |  59%  |                                                                         |=======================================                          |  59%  |                                                                         |=======================================                          |  60%  |                                                                         |=======================================                          |  61%  |                                                                         |========================================                         |  61%  |                                                                         |========================================                         |  62%  |                                                                         |=========================================                        |  62%  |                                                                         |=========================================                        |  63%  |                                                                         |=========================================                        |  64%  |                                                                         |==========================================                       |  64%  |                                                                         |==========================================                       |  65%  |                                                                         |===========================================                      |  65%  |                                                                         |===========================================                      |  66%  |                                                                         |===========================================                      |  67%  |                                                                         |============================================                     |  67%  |                                                                         |============================================                     |  68%  |                                                                         |=============================================                    |  69%  |                                                                         |=============================================                    |  70%  |                                                                         |==============================================                   |  70%  |                                                                         |==============================================                   |  71%  |                                                                         |===============================================                  |  72%  |                                                                         |===============================================                  |  73%  |                                                                         |================================================                 |  73%  |                                                                         |================================================                 |  74%  |                                                                         |================================================                 |  75%  |                                                                         |=================================================                |  75%  |                                                                         |=================================================                |  76%  |                                                                         |==================================================               |  76%  |                                                                         |==================================================               |  77%  |                                                                         |==================================================               |  78%  |                                                                         |===================================================              |  78%  |                                                                         |===================================================              |  79%  |                                                                         |====================================================             |  79%  |                                                                         |====================================================             |  80%  |                                                                         |====================================================             |  81%  |                                                                         |=====================================================            |  81%  |                                                                         |=====================================================            |  82%  |                                                                         |======================================================           |  82%  |                                                                         |======================================================           |  83%  |                                                                         |======================================================           |  84%  |                                                                         |=======================================================          |  84%  |                                                                         |=======================================================          |  85%  |                                                                         |========================================================         |  85%  |                                                                         |========================================================         |  86%  |                                                                         |========================================================         |  87%  |                                                                         |=========================================================        |  87%  |                                                                         |=========================================================        |  88%  |                                                                         |==========================================================       |  89%  |                                                                         |==========================================================       |  90%  |                                                                         |===========================================================      |  90%  |                                                                         |===========================================================      |  91%  |                                                                         |============================================================     |  92%  |                                                                         |============================================================     |  93%  |                                                                         |=============================================================    |  93%  |                                                                         |=============================================================    |  94%  |                                                                         |=============================================================    |  95%  |                                                                         |==============================================================   |  95%  |                                                                         |==============================================================   |  96%  |                                                                         |===============================================================  |  96%  |                                                                         |===============================================================  |  97%  |                                                                         |===============================================================  |  98%  |                                                                         |================================================================ |  98%  |                                                                         |================================================================ |  99%  |                                                                         |=================================================================|  99%  |                                                                         |=================================================================| 100%
```

```r
close(pb)
```

```r
plot(out)
```

![](agroecology_files/figure-html/unnamed-chunk-7-1.png)<!-- -->

```r
test
```

```
## # A tibble: 1 x 9
##   household n_inhabitants storage yield_memory food_ratio inhabitants     
##       <int>         <int>   <dbl> <list>            <dbl> <list>          
## 1         1            55    1762 <dbl [15]>         1.15 <tibble [55 × 1…
## # ... with 3 more variables: laborers <dbl>, land <dbl>, yield <dbl>
```


