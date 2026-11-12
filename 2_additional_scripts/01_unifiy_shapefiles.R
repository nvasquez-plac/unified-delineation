
################################################################
#
# Script to unifiy the shapefiles from all the basins
#
# nicolas.vasquez@ucalgary.ca
#
################################################################

cat("\14")
rm(list = ls())
graphics.off()

library("sf")

################################################################
#         Variables required by the script to run
################################################################

dirShp   <- file.path("/Users/nvasquez/Library/CloudStorage/Dropbox-Personal/UofC/02_dataset_develop/camels_mx/output")
dirSites <- file.path("/Users/nvasquez/Library/CloudStorage/Dropbox-Personal/UofC/02_dataset_develop/camels_mx/sites")

# Load sites
sites <- read.csv( file.path( dirSites, "sites.csv"))

################################################################
#                   Create one file only
################################################################

basins <- NULL
rivers <- NULL

for( iSite in 1:nrow(sites)){

    siteId <- sites$site_id[iSite]

    # Ordinary basins are in tdx_clipped; nested basins (MX_12428, MX_12496, MX_12532) in tdx_nested_preview
    variant <- "tdx_clipped"
    
    if( !dir.exists( file.path( dirShp, siteId, "cwarhm_exports", variant ) ) ) variant <- "tdx_nested_preview"

    dirToBasin <- file.path( dirShp, siteId, "cwarhm_exports", variant, "shapefiles", "river_basins",  paste0(siteId, "_river_basins.shp" ) )
    dirToRiver <- file.path( dirShp, siteId, "cwarhm_exports", variant, "shapefiles", "river_network", paste0(siteId, "_river_network.shp") )

    if( file.exists(dirToBasin) & file.exists(dirToRiver) ){

        basinShp <- st_read( dirToBasin, quiet = TRUE )[, c("COMID", "area_km2")]
        riverShp <- st_read( dirToRiver, quiet = TRUE )[, c("COMID", "NextDownID", "slope", "lengthkm", "length_m")]

        basinShp$basinId <- siteId ; basinShp$variant <- variant
        riverShp$basinId <- siteId ; riverShp$variant <- variant

        basins <- rbind( basins, basinShp)
        rivers <- rbind( rivers, riverShp)

    }else{
        stop("=====01: Incomplete data for basins ", siteId)
    }
}

################################################################
#                         Save files
################################################################


st_write( basins, dsn = file.path(dirShp, "basinsAll.gpkg"), delete_dsn = TRUE)
st_write( rivers, dsn = file.path(dirShp, "riversAll.gpkg"), delete_dsn = TRUE)

################################################################
#                                           Fin. Buena suerte :) 
################################################################
