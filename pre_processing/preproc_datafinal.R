# --------------------------------------------------------------
# 95-845 AAMLP: Final Project
# Nathan Deron, David Contreras, Laura Goyeneche
# Last update: November 27, 2019
# --------------------------------------------------------------

rm(list = ls())

# Define libraries
# --------------------------------------------------------------
libs = c('dplyr',
         'lubridate',
         'rgdal',
         'fastDummies')

# Attach libraries
invisible(suppressMessages(lapply(libs, library, character.only = T)))

# Working directory
# --------------------------------------------------------------
cd = 'C:/Users/lgoye/OneDrive/Documents/Github/aamlp_chicago_rides'
setwd(cd)

# Import data
df_taxi   = readRDS(paste0(cd, '/data_rds/df_taxi_imputed.rds'))
df_other  = readRDS(paste0(cd, '/data_rds/df_other_imputed.rds'))
df_crime  = readRDS(paste0(cd, '/data_rds/df_crime_imputed.rds'))

# Import shapefile
sh_census = readOGR(dsn    = paste0(cd, '/data_shp'), 
                   layer   = 'census_tract',
                   verbose = F)

# Import census data 
census = read.csv(paste0(cd, '/data_rds/census_data.csv'), header = T)

# Pre processing 
# --------------------------------------------------------------

# Rename variables
names(df_taxi)  = gsub("_imputed", "", names(df_taxi), fixed = T)
names(df_other) = gsub("_imputed", "", names(df_other), fixed = T)

# Add variable id_ride 
# id_ride = 1 if ride sharing, 0 otherwise
df_taxi  = df_taxi %>% mutate(id_ride = 0)
df_other = df_other %>% mutate(id_ride = 1)

# Modify census id

names(census) = tolower(names(census))

census = 
  census %>%
  mutate(id = 
           id %>%
           as.character() %>%
           gsub("0800000US" , "", ., fixed = T) %>%
           gsub("1400014000", "", ., fixed = T) %>%
           as.numeric()) %>%
  filter(!is.na(somecollege.rate),
         !is.na(hrs.worked))

# Classify crimes by census tract
# --------------------------------------------------------------
# Select longitude and latitude
temp = 
  df_crime %>%
  select(id, latitude_imputed, longitude_imputed) %>%
  rename(latitude  = latitude_imputed,
         longitude = longitude_imputed)

# Create coordinates
coordinates(temp) = c("longitude", "latitude")

# Assign same reference system
proj4string(temp) = proj4string(sh_census)

# Assign census geoid to each crime id 
temp$census = over(temp, sh_census)$geoid10

# Merge crime with temp 
df_crime = left_join(df_crime, temp@data, by = "id")

rm(temp)

# Drop those observation without census id 
df_crime =
  df_crime %>%
  filter(!is.na(census))

# Collapse df_crime data
crime = 
  df_crime %>%
  select(-id, 
         -date, 
         -primary_type,
         -location_description,
         -beat, 
         -district,
         -year, 
         -month, 
         -hm_start, 
         -h_start,
         -ward_imputed,
         -community_area_imputed,
         -latitude_imputed,
         -longitude_imputed,
         -ward_missing,
         -community_area_missing,
         -latitude_missing,
         -longitude_missing) %>%
  mutate(total_crime = 1) %>%
  group_by(census, day) %>%
  summarise_all(sum) %>%
  ungroup() %>%
  mutate(census = as.numeric(as.character(census)))

# Merge crime with df_taxi and df_other
# --------------------------------------------------------------

# Create temporary data for pickup and dropoff
# Pickup
  # Crime
    temp = crime 
    names(temp) = paste0("pickup_", names(temp))
    
    temp  = temp %>% rename(pickup_census_tract = pickup_census, day = pickup_day)
    
    taxi  = left_join(df_taxi , temp, by = c("pickup_census_tract","day"))
    taxi  = taxi %>% replace(., is.na(.), 0)
    
      rm(df_taxi)
    
    other = left_join(df_other, temp, by = c("pickup_census_tract","day"))
    other = other %>% replace(., is.na(.), 0)
    
      rm(df_other)
    
  # Census
    temp = census 
    names(temp) = paste0("pickup_", names(temp))
  
    temp = temp %>% rename(pickup_census_tract = pickup_id)
    taxi  = left_join(taxi , temp, by = c("pickup_census_tract"))
    other = left_join(other, temp, by = c("pickup_census_tract"))
    
rm(temp)

# Append taxi and other (ride sharing services)
# --------------------------------------------------------------
df_final = 
  taxi %>%
  select(-tolls,
         -tolls_missing,
         -payment_type,
         -company) %>%
  bind_rows((other %>%
               select(-shared_trip_authorized,
                      -trips_pooled))) 

df_final = 
  df_final %>%
  replace(., is.na(.), 0)

# Save data final in RDS format
saveRDS(df_final , paste0(cd, '/data_rds/df_final.rds'))

# --------------------------------------------------------------