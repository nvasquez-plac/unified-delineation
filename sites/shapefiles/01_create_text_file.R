

#############################################################
# Script to create a text file with the basins
#############################################################

library("sf")


dirData <- file.path("/Users/nvasquez/Github/unified-delineation/sites/shapefiles")

shp <- file.path( dirData, "HS_Verified_v09.shp")

x <- st_read( shp )

st_drop_geometry(x)

#############################################################
# Identify duplicated stations
#############################################################

claves <- unique(x$Clave)

if( length(claves) != nrow(x)){
    message("===== There are duplicated rows. Number of IDs (Clave): ", length(claves), " | ",
    "Number of basins: ", nrow(x))
}

# Print the claves:
for( iClave in 1:length(claves)){

    rows <- which( x$Clave == claves[iClave])

    if( length(rows) > 1){
        print("====================================")
        print(paste0("Rows duplicated: ", paste(rows, collapse = "-")) )
        print( st_drop_geometry(x)[rows, c("ID", "Clave", "X", "Y")])
    }
}

#############################################################
# Check the number of characters
#############################################################

nChar <- nchar(x$Clave)

print("===== Number of characters in Clave (n chars | n rows):")
print( table(nChar, useNA = "ifany") )

if( length(unique(nChar)) > 1){
    message("===== Clave does not have the same number of characters in all rows")
    print( st_drop_geometry(x)[nChar != 5, c("ID", "Clave", "Estacion")])
}

x$nCharacClave <- nchar(x$Clave)


#############################################################
# Ensure all stations have five digits. If four, add a zero before.
#############################################################

rowsFour <- which( nchar(x$Clave) == 4 )

if( length(rowsFour) > 0){
    message("===== Adding a leading zero to ", length(rowsFour), " Claves with four digits")
    x$Clave[rowsFour] <- paste0("0", x$Clave[rowsFour])
}

# Recompute the number of characters and stop if any Clave still does not have five
x$nCharacClave <- nchar(x$Clave)

if( any(x$nCharacClave != 5) ){
    print( st_drop_geometry(x)[x$nCharacClave != 5, c("ID", "Clave", "Estacion")])
    stop("===== Some Claves do not have five digits (see rows above)")
}


x$basinId <- paste0("MX_", x$Clave)

#############################################################
# Fix station names: the source data has a literal "?" where an "Ñ" was lost
# (e.g. "LAS PE?ITAS", "BOLA?OS"). All 22 cases checked are Ñ.
#############################################################

rowsQuestion <- which( grepl("?", x$Estacion, fixed = TRUE) )

if( length(rowsQuestion) > 0){
    message("===== Replacing '?' with 'Ñ' in ", length(rowsQuestion), " station names")
    x$Estacion[rowsQuestion] <- gsub("?", "Ñ", x$Estacion[rowsQuestion], fixed = TRUE)
}

#############################################################
# Remove duplicated stations: for each duplicated Clave keep the row with the higher ID
# (IDs 860-867 are a later re-entered batch with corrected coordinates/names)
#############################################################

rowsToRemove <- c()

for( iClave in 1:length(claves)){

    rows <- which( x$Clave == claves[iClave])

    if( length(rows) > 1){

        rowKeep <- rows[ which.max( as.integer(x$ID[rows]) ) ]

        # If the kept row has no station name, take it from the removed row
        if( is.na(x$Estacion[rowKeep]) ){
            x$Estacion[rowKeep] <- x$Estacion[ setdiff(rows, rowKeep)[1] ]
        }

        rowsToRemove <- c(rowsToRemove, setdiff(rows, rowKeep))
    }
}

if( length(rowsToRemove) > 0){
    message("===== Removing ", length(rowsToRemove), " duplicated rows (IDs: ",
            paste(x$ID[rowsToRemove], collapse = ", "), ")")
    x <- x[-rowsToRemove, ]
}

if( any(duplicated(x$Clave)) ){
    stop("===== There are still duplicated Claves")
}

#############################################################
# Save the text file
#############################################################

write.table( st_drop_geometry(x)[, c("basinId", "Estacion", "X", "Y")],
            sep       = "|",
            file      = file.path(dirData, "HS_Verified_v09.txt"),
            row.names = FALSE,
            quote     = FALSE)


#############################################################
#                                        Fin. Buena suerte :)
#############################################################
