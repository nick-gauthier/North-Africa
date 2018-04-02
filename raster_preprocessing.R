library(raster)
library(tidyverse)
library(mgcv)
library(SPEI)

bbox <- extent(5, 11.5, 34, 37.5)

prec <- list.files('~/Data/Chelsa/prec', full.names = T) %>% 
  stack %>%
  crop(bbox) %>%
  .[[c(4:12, 1:3)]] # this order can vary, always confirm!

temp <- list.files('~/Data/Chelsa/temp/', full.names = T) %>% 
  stack %>%
  crop(bbox) %>%
  `/`(10) %>%
  .[[c(3, 5:12, 1:2, 4)]] 

tmin <- list.files('~/Data/Chelsa/tmin/', full.names = T) %>% 
  stack %>%
  crop(bbox) %>%
  `/`(10) %>%
  .[[c(3, 5:12, 1:2, 4)]] # this order can vary, always confirm!

tmax <- list.files('~/Data/Chelsa/tmax/', full.names = T) %>% 
  stack %>%
  crop(bbox) %>%
  `/`(10) %>%
  .[[c(3, 5:12, 1:2, 4)]] # this order can vary, always confirm!

writeRaster(prec, 'data/CHELSA/prec_1km.tif', overwrite = T)
writeRaster(temp, 'data/CHELSA/temp_1km.tif', overwrite = T)
writeRaster(tmin, 'data/CHELSA/tmin_1km.tif', overwrite = T)
writeRaster(tmax, 'data/CHELSA/tmax_1km.tif', overwrite = T)

gdd5_interp <- function(x){
  if(any(is.na(x))){return(NA)} else{
    daily <- gam(x ~ s(doy, bs = 'cc', k = 12), knots = list(doy = c(1, 366))) %>%
      predict.gam(data.frame(doy = 1:365)) 
    daily[daily < 5] <- 5
    return(sum(daily - 5))
  }
}

doy <-c(15, 46, 74, 105, 135, 166, 196, 227, 258, 288, 319, 349)

beginCluster(4)
gdd5 <- clusterR(temp, calc, args = list(fun = gdd5_interp), export = 'doy')
endCluster()
writeRaster(gdd5, 'data/CHELSA/gdd5_1km.tif', overwrite = T)

srad <- list.files('~/Data/ET_SolRad', full.names = T) %>%
  stack %>%
  raster::resample(prec) %>%
  mask(prec) %>%
  .[[c(1, 5:12, 2:4)]] %>%
  `*`(2.45) #convert to mj/m2/day


pet <- hargreaves(tmin %>% getValues %>% t, 
                  tmax %>% getValues %>% t, 
                  Ra = srad %>% getValues %>% t, 
                  Pre = prec %>% getValues %>% t, na.rm = T) %>%
  t %>%
  setValues(tmin, .)

writeRaster(pet, 'data/CHELSA/pet_1km.tif', overwrite = T)
rm(srad, tmax, tmin)

swc <- setValues(pet[[1]], 100) %>% mask(pet[[1]])
aet.brick <- setValues(pet, 0) %>% mask(pet[[1]])

for(a in 1:10){
  for(i in 1:12){
    ksoil <- swc / 350
    aet <- pet[[i]] * ksoil
    aet.brick[[i]] <- aet
    swc.tmp <- swc + prec[[i]] * (1 - .15) - aet
    swc <- reclassify(swc.tmp, c(-Inf, 0, 0, 350, Inf, 350))
  }
}

plot(aet.brick)

alpha <- sum(aet.brick) / sum(pet)
writeRaster(alpha, 'data/CHELSA/alpha_1km.tif', overwrite = T)
