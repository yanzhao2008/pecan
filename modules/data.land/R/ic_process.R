##' @name ic_process
##' @title ic_process
##' @export
##'
##' @param settings pecan settings list
##' @param dbfiles where to write files
##' @param overwrite whether to force ic_process to proceed
##' @author Istem Fer
ic_process <- function(settings, input, dir, overwrite = FALSE){
  
  
  #--------------------------------------------------------------------------------------------------#
  # Extract info from settings and setup
  site       <- settings$run$site
  model      <- settings$model$type
  host       <- settings$host
  dbparms    <- settings$database
  
  # Handle IC Workflow locally
  if(host$name != "localhost"){
    host$name <- "localhost"
    dir       <- settings$database$dbfiles
  }
  
  # If overwrite is a plain boolean, fill in defaults for each module
  if (!is.list(overwrite)) {
    if (overwrite) {
      overwrite <- list(getveg = TRUE,  putveg = TRUE)
    } else {
      overwrite <- list(getveg = FALSE, putveg = FALSE)
    }
  } else {
    if (is.null(overwrite$getveg)) {
      overwrite$getveg <- FALSE
    }
    if (is.null(overwrite$putveg)) {
      overwrite$putveg <- FALSE
    }
  }
  
  # set up bety connection
  bety <- dplyr::src_postgres(dbname   = dbparms$bety$dbname, 
                              host     = dbparms$bety$host, 
                              user     = dbparms$bety$user, 
                              password = dbparms$bety$password)
  
  con <- bety$con
  on.exit(db.close(con))
  
  ## We need two types of start/end dates now
  ## i)  start/end of the run when we have no veg file to begin with (i.e. we'll be querying a DB)
  ## ii) start and end of the veg file if we'll load veg data from a source file, this could be different than model start/end
  # query (ii) from source id [input id in BETY]
  
  # this check might change depending on what other sources that requires querying its own DB we will have
  # probably something passed from settings
  if(input$source == "FIA"){ 
    
    start_date <- settings$run$start.date
    end_date   <- settings$run$end.date
  }else{
    
   query      <- paste0("SELECT * FROM inputs where id = ", input$source.id)
   input_file <- db.query(query, con = con) 
   start_date <- input_file$start_date
   end_date   <- input_file$end_date
    
  }
  # set up host information
  machine.host <- ifelse(host == "localhost" || host$name == "localhost", PEcAn.remote::fqdn(), host$name)
  machine <- db.query(paste0("SELECT * from machines where hostname = '", machine.host, "'"), con)
  
  # retrieve model type info
  if(is.null(model)){
    modeltype_id <- db.query(paste0("SELECT modeltype_id FROM models where id = '", settings$model$id, "'"), con)[[1]]
    model <- db.query(paste0("SELECT name FROM modeltypes where id = '", modeltype_id, "'"), con)[[1]]
  }
  
  # setup site database number, lat, lon and name and copy for format.vars if new input
  new.site <- data.frame(id = as.numeric(site$id), 
                         lat = PEcAn.data.atmosphere::db.site.lat.lon(site$id, con = con)$lat, 
                         lon = PEcAn.data.atmosphere::db.site.lat.lon(site$id, con = con)$lon)
  new.site$name <- settings$run$site$name
  

str_ns <- paste0(new.site$id %/% 1e+09, "-", new.site$id %% 1e+09)
  
  
outfolder <- file.path(dir, paste0(input$source, "_site_", str_ns))

   
getveg.id <- putveg.id <- NULL
  
  
#--------------------------------------------------------------------------------------------------#
  # Load/extract + match species module
  
if (is.null(getveg.id) & is.null(putveg.id)) {

    getveg.id <-.get.veg.module(input_veg = input, 
                              outfolder = outfolder, 
                              start_date = start_date, end_date = end_date,
                              dbparms = dbparms,
                              new_site = new.site,
                              host = host, 
                              machine_host = machine.host,
                              overwrite = overwrite$getveg)

  }
  

#--------------------------------------------------------------------------------------------------#
  # Match species to PFTs + veg2model module
  
  if (!is.null(getveg.id) & is.null(putveg.id)) { # probably need a more sophisticated check here
    
    putveg.id <-.put.veg.module(getveg.id = getveg.id, dbparms = dbparms,
                                input_veg = input, pfts = settings$pfts,
                                outfolder = outfolder, 
                                dir = dir, machine = machine, model = model,
                                start_date = start_date, end_date = end_date,
                                new_site = new.site,
                                host = host, overwrite = overwrite$putveg)
    
  }

  #--------------------------------------------------------------------------------------------------#
  # Fill settings
  if (!is.null(putveg.id)) {
    
    
    model_file <- db.query(paste("SELECT * from dbfiles where container_id =", putveg.id), con)
    
    # now that we don't have multipasses, convert.input only inserts 1st filename
    # do we want to change it in convert.inputs such that it loops over the dbfile.insert?
    path_to_settings <- file.path(model_file[["file_path"]], model_file[["file_name"]])
    settings$run$inputs[[input$output]][['path']] <- path_to_settings
    
    # NOTE : THIS BIT IS SENSITIVE TO THE ORDER OF TAGS IN PECAN.XML
    # this took care of "css" only, others have the same prefix
    if(input$output == "css"){  
      settings$run$inputs[["pss"]][['path']]  <- gsub("css","pss", path_to_settings)
      settings$run$inputs[["site"]][['path']] <- gsub("css","site", path_to_settings)
      
      # IF: For now IC workflow is only working for ED and it's the only case for copying to remote
      # but this copy to remote might need to go out of this if-block and change
      
      # Copy to remote, update DB and change paths if needed
      if (settings$host$name != "localhost") {
        
        remote_dir <- file.path(settings$host$folder, paste0(input$source, "_site_", str_ns))
        
        # copies css
        css_file <- basename(settings$run$inputs[["css"]][['path']])
        PEcAn.remote::remote.copy.update(putveg.id, remote_dir, remote_file_name = css_file, settings$host, con)
        settings$run$inputs[["css"]][['path']] <- file.path(remote_dir, css_file)
        
        # pss 
        pss_file <-  basename(settings$run$inputs[["pss"]][['path']])
        PEcAn.remote::remote.copy.update(putveg.id, remote_dir, remote_file_name = pss_file, settings$host, con)
        settings$run$inputs[["pss"]][['path']] <- file.path(remote_dir, pss_file)
          
        # site
        site_file <- basename(settings$run$inputs[["site"]][['path']])
        PEcAn.remote::remote.copy.update(putveg.id, remote_dir, remote_file_name = site_file, settings$host, con)
        settings$run$inputs[["site"]][['path']] <- file.path(remote_dir, site_file)
        
      }
    }
    
  }
  
  
  return(settings)
} # ic_process
