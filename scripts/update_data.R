#!/usr/bin/env Rscript
# Read-only ESPN data snapshots. No predictions and no invented statistics.
suppressPackageStartupMessages({library(hoopR);library(jsonlite)})
options(timeout=90)
Sys.setenv(TZ="America/New_York")
root <- "public/data"
dir.create(file.path(root,"dates"), recursive=TRUE, showWarnings=FALSE)
dir.create(file.path(root,"games"), recursive=TRUE, showWarnings=FALSE)
now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz="UTC")
text <- function(x, fallback="") {if(is.null(x)||length(x)==0||is.na(x[1]))return(fallback);as.character(x[1])}
first <- function(row, names, fallback="") {for(n in names)if(n %in% names(row)&&length(row[[n]])&& !is.na(row[[n]][1]))return(text(row[[n]],fallback));fallback}
write_json <- function(path, value) {
  tmp <- paste0(path,".tmp")
  writeLines(jsonlite::toJSON(value,auto_unbox=TRUE,null="null",na="null",POSIXt="ISO8601",digits=NA,pretty=TRUE),tmp,useBytes=TRUE)
  if(!file.rename(tmp,path))stop("Could not publish ",path)
}
# Discard huge/list-valued columns from generic tables? No: serialize JSON, then render safely in UI.
rows <- function(obj) {
  if(is.null(obj))return(list())
  if(is.data.frame(obj))return(unname(lapply(seq_len(nrow(obj)),function(i) lapply(obj[i,,drop=FALSE],function(v) if(is.factor(v))as.character(v) else if(length(v)==1) unname(v) else v))))
  if(is.list(obj) && !is.null(names(obj)) && length(obj) && all(vapply(obj,is.data.frame,logical(1))))return(unlist(lapply(names(obj),function(n){v<-rows(obj[[n]]);lapply(v,function(r)c(list(result_set=n),r))}),recursive=FALSE))
  if(is.list(obj) && length(obj) && is.null(names(obj)))return(obj)
  if(is.list(obj))return(list(obj))
  list(list(value=as.character(obj)))
}
call_espn <- function(fun, args=list(), sleep=1.1) {
  if(!fun %in% getNamespaceExports("hoopR"))return(list(ok=FALSE,error="Function is unavailable in installed hoopR",data=NULL))
  f <- getExportedValue("hoopR",fun)
  allowed <- names(formals(f))
  args <- args[names(args) %in% allowed]
  Sys.sleep(sleep)
  tryCatch({v<-do.call(f,args);list(ok=TRUE,error=NULL,data=v)},error=function(e)list(ok=FALSE,error=conditionMessage(e),data=NULL))
}
section <- function(label, fun, args=list()) {
  result <- call_espn(fun,args)
  data <- if(result$ok) rows(result$data) else list()
  cat(sprintf("  %-39s %s [%d rows]\n",fun,if(result$ok)"OK" else "FAIL",length(data)))
  if(!result$ok)message("    ",result$error)
  list(label=label,`function`=fun,updatedAt=now(),status=if(!result$ok)"error" else if(length(data)==0)"empty" else "ok",rows=data,error=result$error)
}
# Handle ESPN scoreboard versions whose column naming conventions differ.
as_game <- function(r, date) {
  id <- first(r,c("game_id","event_id","id","gameId"))
  if(!nzchar(id))return(NULL)
  away <- list(id=first(r,c("away_team_id","away_id","awayTeamId")),
    name=first(r,c("away_team_full_name","away_team_display_name","away_team_name","away_display_name","away_team","awayTeamName"),"Away team"),
    abbreviation=first(r,c("away_team_abb","away_team_abbreviation","away_abbreviation","away_team_short_name","awayTeamAbbreviation"),"AWY"),
    score=first(r,c("away_score","away_team_score","away_points"),NA_character_),record=first(r,c("away_record","away_team_record"),NA_character_))
  home <- list(id=first(r,c("home_team_id","home_id","homeTeamId")),
    name=first(r,c("home_team_full_name","home_team_display_name","home_team_name","home_display_name","home_team","homeTeamName"),"Home team"),
    abbreviation=first(r,c("home_team_abb","home_team_abbreviation","home_abbreviation","home_team_short_name","homeTeamAbbreviation"),"HME"),
    score=first(r,c("home_score","home_team_score","home_points"),NA_character_),record=first(r,c("home_record","home_team_record"),NA_character_))
  list(id=id,date=date,time=first(r,c("game_date_time","game_date","date","game_datetime","start_date","start_time"),NA_character_),
       status=first(r,c("status_type_description","status_name","status","status_type_name","status_detail","game_status"),"Scheduled"),away=away,home=home)
}
# ESPN scoreboard may use team competitor columns; preserve raw scoreboard below for diagnosis.
get_games <- function(board, date) {
  if(!is.data.frame(board)) {
    if(is.list(board)&&is.data.frame(board$games))board<-board$games else stop("Scoreboard returned unsupported structure. See ESPN response in workflow logs.")
  }
  if(nrow(board)==0)return(list())
  if("game_date" %in% names(board)) {
    board <- board[substr(as.character(board$game_date),1,10)==date,,drop=FALSE]
  } else if("game_date_time" %in% names(board)) {
    board <- board[format(as.POSIXct(board$game_date_time),"%Y-%m-%d",tz="America/New_York")==date,,drop=FALSE]
  } else stop("Scoreboard has no recognized date column")
  if(nrow(board)==0)return(list())
  out<-lapply(seq_len(nrow(board)),function(i)as_game(as.list(board[i,,drop=FALSE]),date))
  Filter(Negate(is.null),out)
}
requested <- Sys.getenv("NBA_DATE","")
if(nzchar(requested) && !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$",requested))stop("NBA_DATE must be YYYY-MM-DD")
dates <- if(nzchar(requested)) as.Date(requested) else seq(Sys.Date()-1,Sys.Date()+2,by="day")
for(date in as.character(dates)) {
  day <- as.Date(date)
  cat("\nFetching ESPN NBA for ",date,"\n",sep="")
  season_year <- if(as.integer(format(day,"%m")) >= 7) as.integer(format(day,"%Y")) + 1L else as.integer(format(day,"%Y"))
  board <- call_espn("espn_nba_scoreboard",list(season=season_year))
  if(!board$ok) {message("Scoreboard failed for ",date,": ",board$error,"; keeping previous snapshot");next}
  games <- tryCatch(get_games(board$data,date),error=function(e){message("Scoreboard parse failed: ",conditionMessage(e));NULL})
  if(is.null(games)){next}
  # Do not overwrite a previously populated date with an unexpectedly empty feed.
  path <- file.path(root,"dates",paste0(date,".json"))
  if(length(games)==0 && file.exists(path)) {
    prev <- tryCatch(jsonlite::fromJSON(path,simplifyVector=FALSE),error=function(e)NULL)
    if(length(prev$games)>0) {message("Empty scoreboard on a previously populated date; retaining old snapshot");next}
  }
  # A small league wide payload is fetched once per day, not once per game.
  league <- if(date==format(Sys.Date(),"%Y-%m-%d")) list(section("League standings","espn_nba_standings"),section("NBA injuries","espn_nba_injuries")) else list()
  write_json(path,list(date=date,updatedAt=now(),source="ESPN via hoopR",games=games,sections=league,errors=list()))
  cat("Published ",length(games)," games\n",sep="")
  for(game in games) {
    id<-game$id; outpath<-file.path(root,"games",paste0(id,".json"))
    # Team-level endpoints require a valid ESPN team id from the scoreboard.
    game_sections<-list(
      section("Game broadcasts","espn_nba_game_broadcasts",list(event_id=id)),
      section("Game odds","espn_nba_game_odds",list(event_id=id)),
      section("Game officials","espn_nba_game_officials",list(event_id=id)))
    for(side in c("away","home")){
      team<-game[[side]]; team_id<-team$id
      if(!nzchar(team_id))next
      tag<-if(side=="away")"Away" else "Home"
      season<-as.integer(format(day+75,"%Y")) # season ending in spring; Oct maps to next year
      game_sections<-c(game_sections,list(
        section(paste(tag,"Team statistics"),"espn_nba_team_stats",list(team_id=team_id,season=season)),
        section(paste(tag,"Team schedule"),"espn_nba_team_schedule",list(team_id=team_id,season=season)),
        section(paste(tag,"Team roster"),"espn_nba_team_roster",list(team_id=team_id,season=season)),
        section(paste(tag,"Team injuries"),"espn_nba_team_injuries",list(team_id=team_id)),
        section(paste(tag,"Team leaders"),"espn_nba_team_leaders",list(team_id=team_id,season=season))))
    }
    # Include box scores only for games ESPN labels final or in progress.
    if(grepl("final|progress|quarter|half|q[1-4]",game$status,ignore.case=TRUE))
      game_sections<-c(game_sections,list(section("Player box score","espn_nba_player_box",list(game_id=id)),section("Team box score","espn_nba_team_box",list(game_id=id))))
    # Preserve prior nonempty sections if ESPN temporarily fails.
    if(file.exists(outpath)){
      previous<-tryCatch(jsonlite::fromJSON(outpath,simplifyVector=FALSE),error=function(e)NULL)
      if(!is.null(previous$sections)) for(i in seq_along(game_sections)) {
        s<-game_sections[[i]]
        old<-Filter(function(x)identical(x[["function"]],s[["function"]])&&identical(x$label,s$label)&&identical(x$status,"ok"),previous$sections)
        if(s$status!="ok" && length(old))game_sections[[i]]<-old[[1]]
      }
    }
    write_json(outpath,list(game=game,updatedAt=now(),sections=game_sections))
    cat("Published event ",id,"\n",sep="")
  }
}
write_json(file.path(root,"index.json"),list(schemaVersion=1,lastRun=now(),dates=sort(sub("\\.json$","",list.files(file.path(root,"dates"),pattern="\\.json$")),decreasing=TRUE)))
