# Modern Climate
Nick Gauthier  
6/7/2017  



## Present Day Climate in North Africa

```r
library(raster)
```

```
## Loading required package: sp
```

```r
library(tidyverse)
```

```
## Loading tidyverse: ggplot2
## Loading tidyverse: tibble
## Loading tidyverse: tidyr
## Loading tidyverse: readr
## Loading tidyverse: purrr
## Loading tidyverse: dplyr
```

```
## Conflicts with tidy packages ----------------------------------------------
```

```
## extract(): tidyr, raster
## filter():  dplyr, stats
## lag():     dplyr, stats
## select():  dplyr, raster
```

```r
library(ClimClass)
library(parallel)
```



```r
prec <- getData('worldclim', var = 'prec', res = 2.5) %>%
  crop(extent(-10, 15, 30, 38))

na.clump <- clump(prec[[1]])
```

```
## Loading required namespace: igraph
```

```r
prec <- mask(prec, na.clump, maskvalue = 6, inverse = T)

tmin <- getData('worldclim', var = 'tmin', res = 2.5) %>%
  crop(extent(-10, 15, 30, 38)) %>%
  mask(na.clump, maskvalue = 6, inverse = T) %>%
  `/`(10)

tmax <- getData('worldclim', var = 'tmax', res = 2.5) %>%
  crop(extent(-10, 15, 30, 38)) %>%
  mask(na.clump, maskvalue = 6, inverse = T) %>%
  `/`(10)
```


```r
koeppen_map <- function(x){
  ifelse(is.na(prec[x][1]), 
         return(NA),
      return(data_frame(month = 1:12,
           P = c(prec[x]),
           Tx = c(tmax[x]),
           Tn = c(tmin[x])) %>%
    mutate(Tm = (Tx + Tn) / 2) %>%
    koeppen_geiger(clim.resume_verbose = F) %>%
    .$class %>%
      as.character))
}


clim_class <- mclapply(1:ncell(prec), koeppen_map, mc.cores = detectCores()) %>% 
  unlist %>%
  as.factor %>%
  setValues(prec[[1]], .)
```


```r
class_names <- c(
  BSh = 'Hot semi-arid',
  BSk = 'Cold semi-arid',
  BWh = 'Hot desert',
  BWk = 'Cold desrt',
  Csa = 'Hot-summer Mediterranean',
  Csb = 'Warm-summer Mediterranean',
  Dsb = 'Warm, dry-summer contiental',
  Dsc = 'Dry-summer subarctic'
)
```



```r
clim_class %>% 
  as.data.frame(xy = T, na.rm = T) %>%
  mutate(class = recode_factor(prec1_VALUE, BSh = 'Hot semi-arid',
  BSk = 'Cold semi-arid',
  BWh = 'Hot desert',
  BWk = 'Cold desrt',
  Csa = 'Hot-summer Mediterranean',
  Csb = 'Warm-summer Mediterranean',
  Dsb = 'Warm, dry-summer continental',
  Dsc = 'Dry-summer subarctic')) %>%
  ggplot(aes(x, y, fill = class)) +
  geom_raster() +
  labs(title = 'Present day climate of North Africa', subtitle = 'Based on WorldClim data') +
  scale_fill_discrete(name = 'Köppen-Geiger classification') +
  theme_void() +
  coord_quickmap()
```

![](Modern_Climate_files/figure-html/unnamed-chunk-5-1.png)<!-- -->

