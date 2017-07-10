library(raster)
library(mgcv)
library(mail)

temp <- brick('Data/CHELSA/temp.nc')


gdd0_interp <- function(x){
  if(any(is.na(x))){return(NA)} else{
    daily <- gam(x ~ s(doy, bs = 'cc', k = 12), knots = list(doy = c(1, 366))) %>%
      predict.gam(data.frame(doy = 1:365)) 
    daily[daily < 0] <- 0
    return(sum(daily - 0))
  }
}

gdd5_interp <- function(x){
  if(any(is.na(x))){return(NA)} else{
    daily <- gam(x ~ s(doy, bs = 'cc', k = 12), knots = list(doy = c(1, 366))) %>%
      predict.gam(data.frame(doy = 1:365)) 
    daily[daily < 5] <- 5
    return(sum(daily - 5))
  }
}

doy <-c(15, 46, 74, 105, 135, 166, 196, 227, 258, 288, 319, 349)

finished_email <- mime(
  To = 'ngauthier91@gmail.com',
  From = 'ngauthier91@gmail.com',
  Subject = "Job's done",
  body = "yup")


beginCluster(4)
gdd0 <- clusterR(temp, calc, args = list(fun = gdd0_interp), export = 'doy')
gdd5 <- clusterR(temp, calc, args = list(fun = gdd5_interp), export = 'doy')
endCluster()

writeRaster(gdd0, 'gdd0_global.tif', overwrite = T)
writeRaster(gdd5, 'gdd5_global.tif', overwrite = T)

send_message(finished_email)



gdd0 <- raster('gdd0_global.tif')
gdd5 <- raster('gdd5_global.tif')

plot(gdd5)
plot(gdd0)
