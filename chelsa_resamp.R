#Resample  chelsa maps to 5minutes

library(raster)
library(tidyverse)

wheat.area <- raster('~/Downloads/Ramankutty Crops/wheat_HarvAreaYield2000_Geotiff/wheat_HarvAreaYield2000_Geotiff/wheat_HarvestedAreaFraction.tif')

resamp_chelsa <- function(x){
  list.files(x, full.names = T) %>% 
  stack %>%
  resample(wheat.area) %>%
  .[[c(1,5:12, 2:4)]]
}

temp <- resamp_chelsa('~/Downloads/CHELSA/temp/') %>%
                         `/`(10)
rasterVis::levelplot(temp)
writeRaster(temp, 'temp.nc')
rm(temp)

prec <- resamp_chelsa('~/Downloads/CHELSA/prec/')
rasterVis::levelplot(prec)
writeRaster(prec, 'prec.nc')
rm(prec) 


tmax <- resamp_chelsa('~/Downloads/CHELSA/tmax/') %>%
  `/`(10)
rasterVis::levelplot(tmax)
writeRaster(tmax, 'tmax.nc')
rm(tmax)

tmin <- resamp_chelsa('~/Downloads/CHELSA/tmin/') %>%
  `/`(10)
rasterVis::levelplot(tmin)
writeRaster(tmin, 'tmin.nc')
rm(tmin)