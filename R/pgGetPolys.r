# pgGetPolys
#
#' @title Load a polygon geometry stored in a PostgreSQL database into R.
#'
#' @param conn A connection object created in RPostgreSQL package.
#' @param table character, Name of the schema-qualified table in 
#' Postgresql holding the geometry.
#' @param geom character, Name of the column in 'table' holding the 
#' geometry object (Default = 'geom')
#' @param gid character, Name of the column in 'table' holding the ID 
#' for each polygon geometry. Should be unique if additional columns 
#' of unique data are being appended. (Default = 'gid')
#' @param proj numeric, Can be set to TRUE to automatically take the
#' SRID for the table in the database. Alternatively, the number of
#' EPSG-specified projection of the geometry (Default is NULL, 
#' resulting in no projection.)
#' @param other.cols character, names of additional columns from table
#' (comma-seperated) to append to dataset (Default is all columns, 
#' other.cols=NULL returns a SpatialPolygons object)
#' @param query character, additional SQL to append to modify 
#' select query from table
#' @author David Bucklin \email{david.bucklin@gmail.com}
#' @export
#' @return SpatialPolygonsDataFrame or SpatialPolygons
#' @examples
#' \dontrun{
#' library(RPostgreSQL)
#' drv<-dbDriver("PostgreSQL")
#' conn<-dbConnect(drv,dbname='dbname',host='host',port='5432',
#'                user='user',password='password')
#'
#' pgGetPolys(conn,'schema.tablename')
#' pgGetPolys(conn,'schema.states',geom='statesgeom',gid='state_ID',
#'            other.cols='area,population', 
#'            query = "AND area > 1000000 ORDER BY population LIMIT 10")
#' }

pgGetPolys <- function(conn, table, geom = "geom", gid = NULL, 
                       other.cols = "*", query = NULL) {
  
  ## Check and prepare the schema.name
  if (length(table) %in% 1:2) {
    table <- paste(table, collapse = ".")
  } else {
    stop("The table name should be \"table\" or c(\"schema\", \"table\").")
  }
  
  ## Retrieve the SRID
  str <- paste0("SELECT DISTINCT(ST_SRID(", geom, ")) FROM ", 
                table, " WHERE ", geom, " IS NOT NULL;")
  srid <- dbGetQuery(conn, str)
  ## Check if the SRID is unique, otherwise throw an error
  if (nrow(srid) != 1) 
    stop("Multiple SRIDs in the line geometry")
  
  if (is.null(gid)) {
    gid <- "row_number() over()"
  }
  
  if (is.null(other.cols)) {
    que <- paste0("select ", gid, " as tgid,st_astext(", 
                  geom, ") as wkt from ", table, " where ", geom, " is not null ", 
                  query, ";")
    dfTemp <- suppressWarnings(dbGetQuery(conn, que))
    row.names(dfTemp) = dfTemp$tgid
  } else {
    que <- paste0("select ", gid, " as tgid,st_astext(", 
                  geom, ") as wkt,", other.cols, " from ", table, " where ", 
                  geom, " is not null ", query, ";")
    dfTemp <- suppressWarnings(dbGetQuery(conn, que))
    row.names(dfTemp) = dfTemp$tgid
  }
  
  p4s <- CRS(paste0("+init=epsg:", srid$st_srid))@projargs
  tt <- mapply(function(x, y, z) readWKT(x, y, z), x = dfTemp[, 
                                                              2], y = dfTemp[, 1], z = p4s)
  
  Spol <- SpatialPolygons(lapply(1:length(tt), function(i) {
    lin <- slot(tt[[i]], "polygons")[[1]]
    slot(lin, "ID") <- slot(slot(tt[[i]], "polygons")[[1]], 
                            "ID")  ##assign original ID to polygon
    lin
  }))
  
  Spol@proj4string <- slot(tt[[1]], "proj4string")
  
  if (is.null(other.cols)) {
    return(Spol)
  } else {
    try(dfTemp[geom] <- NULL)
    try(dfTemp["wkt"] <- NULL)
    spdf <- SpatialPolygonsDataFrame(Spol, dfTemp)
    spdf@data["tgid"] <- NULL
    return(spdf)
  }
} 