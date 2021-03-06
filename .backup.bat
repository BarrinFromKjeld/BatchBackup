@echo off 
setlocal

REM CONFIG 
set "NUM_THREADS=8"
set "DICT_SIZE=1g"
set "RETENTION=1"
set "RECOVERY_RECORDS=3"
set "MAX_PARALLEL_COPY=7"

title Backup

REM Get date locale independent 
set "_yyyy=0000"
set "_mm=00"
FOR /F "skip=1 tokens=1-6" %%G IN ('WMIC Path Win32_LocalTime Get Day^,Hour^,Minute^,Month^,Second^,Year /Format:table') DO (
   IF "%%~L"=="" GOTO :EXIT
      set "_yyyy=%%L"
      set "_mm=%%J"
)
:EXIT

set "LOGFILE=backup.log"
set "WINRAR=%ProgramFiles%\WinRAR\winrar.exe"
set "YEAR=%_yyyy%"
set "MONTH=%_mm%"
set "MONTH_BUFF=0%_mm%"
set "MONTH_BUFF=%MONTH_BUFF:~-2%
set "BACKUPFILE=%YEAR%-%MONTH_BUFF%_backup.rar"
set "INFILE=.LocationsToBackup.lst"
set "EXCLUDE_FILE=.ExcludeFromBackup.lst"
set "ADDIT_FILE=.AdditionalLocations.lst"
set "LOCK_FILES=%temp%\backupwait.%random%.lock"
for /l %%N in (1 1 %MAX_PARALLEL_COPY%) do set "cpu%%N="

echo.
echo.
call:EchoAndLog "------------------------------------------------------------"
call:EchoAndLog "-                         BACKUP                           -"
call:EchoAndLog "------------------------------------------------------------"
echo.
echo.
call:Log "%date% %time%"
call:Log "CONFIG"
call:Log "LOGFILE:          %LOGFILE%"
call:Log "WINRAR:           %WINRAR%"
call:Log "YEAR:             %YEAR%"
call:Log "MONTH:            %MONTH%"
call:Log "MONTH_BUFF        %MONTH_BUFF%"
call:Log "BACKUPFILE:       %BACKUPFILE%"
call:Log "INFILE:           %INFILE%"
call:Log "EXCLUDE_FILE:     %EXCLUDE_FILE%"
call:Log "ADDIT_FILE:       %ADDIT_FILE%"
call:Log "LOCK_FILES:       %LOCK_FILES%"
call:Log "NUM_THREADS:      %NUM_THREADS%"
call:Log "DICT_SIZE:        %DICT_SIZE%"
call:Log "RETENTION:        %RETENTION%"
call:Log "RECOVERY_RECORDS: %RECOVERY_RECORDS%"

REM check needed files
if not exist "%WINRAR%" GOTO :EXIT_2
if not exist "%INFILE%" GOTO :EXIT_3
if not exist "%EXCLUDE_FILE%" GOTO :EXIT_4

set /a "MONTH_O=%MONTH%-%RETENTION%"
set /a "YEAR_O=%YEAR%"
if %RETENTION% EQU 0 GOTO :STOP_RETENTION_CALC

call:Log "Berechne Retention Jahr und Monat:"
call:Log " MONTH_O: %MONTH_O%"
call:Log " YEAR_O:  %YEAR_O%"
:START
	if %MONTH_O% GTR 0 GOTO :STOP_RETENTION_CALC
	if %YEAR_O% LEQ 0 GOTO :STOP_RETENTION_CALC
	set /a "MONTH_O=%MONTH_O%+12"
	set /a "YEAR_O=%YEAR_O%-1"
	call:Log " MONTH_O: %MONTH_O%"
	call:Log " YEAR_O: %YEAR_O%"
GOTO :START
:STOP_RETENTION_CALC

REM Pad digits with leading zeros
set "MONTH=00%MONTH%"
set "MONTH_O=00%MONTH_O%"
set "MONTH=%MONTH:~-2%"
set "MONTH_O=%MONTH_O:~-2%"
call:Log "MONTH: %MONTH%"
call:Log "MONTH_O: %MONTH_O%"

call:EchoAndLog "Following files will be backed up:"
FOR /F "eol=; tokens=*" %%i in (%INFILE%) DO (
	call:EchoAndLog " %%i"
)
echo.
call:EchoAndLog "Following files will be excluded:"
FOR /F "eol=; tokens=*" %%i in (%EXCLUDE_FILE%) DO (
	call:EchoAndLog " %%i"
)
echo.
if %RETENTION% EQU 0 GOTO :RETENTION_END 
	call:EchoAndLog "Search old Backups" 
	set "NOTHING_DELETED=Y"
	for %%g in (????-??_backup.rar) do ( 	
		call:RetentionRemoval "%%~nxg"
	)
	call:Log " NOTHING_DELETED: %NOTHING_DELETED%"
	if "%NOTHING_DELETED%" == "Y" (
		call:EchoAndLog " Nothing old found" 
	)
	GOTO :CREATE_ARCHIVE
:RETENTION_END
	echo.
	call:EchoAndLog "Retention set to 0. Old backups will be ignored"

:CREATE_ARCHIVE
if exist "%BACKUPFILE%" GOTO :REFRESH_ARCHIVE
	echo.
	call:EchoAndLog "%BACKUPFILE% will be created" 
	GOTO :WINRAR_CALL
:REFRESH_ARCHIVE
	echo.
	call:EchoAndLog "%BACKUPFILE% will be updated"
:WINRAR_CALL	

echo.
call:EchoAndLog "calling: %WINRAR% u -m5 -ma5 -md%DICT_SIZE% -mt%NUM_THREADS% -rr%RECOVERY_RECORDS% -t -tl -x@%EXCLUDE_FILE% %BACKUPFILE% @%INFILE%"
"%WINRAR%" u -m5 -ma5 -md%DICT_SIZE% -mt%NUM_THREADS% -rr%RECOVERY_RECORDS% -t -tl -x@"%EXCLUDE_FILE%" "%BACKUPFILE%" @"%INFILE%" >>"%LOGFILE%" 2>&1

echo.
call:EchoAndLog "Copying backed up rar file to additional locations in parallel"
setlocal enableDelayedExpansion

call:Log "Initialize Counter"
set "PROCESS_START_COUNTER=0"
set "PROCESS_END_COUNTER=0"

for /l %%N in (1 1 %MAX_PARALLEL_COPY%) do set "END_PROC%%N="

set "LAUNCH=1"
for /F "tokens=*" %%A in (%ADDIT_FILE%) do ( 
	call:EchoAndLog " Copying to %%A"
	if !PROCESS_START_COUNTER! LSS %MAX_PARALLEL_COPY% (
		set /a "PROCESS_START_COUNTER+=1"
		set "NEXT_PROC=!PROCESS_START_COUNTER!"
	) else (
		call:Log " Wait for lock before spawning the next copy"
		call :WaitForLock
	)
	call:Log "  PROCESS_START_COUNTER: !PROCESS_START_COUNTER!"
	set "CURRENT_CMD=copy /Y /B "%BACKUPFILE%" "%%A\%BACKUPFILE%""
	call:Log "  command: !CURRENT_CMD!"
	call:Log "   process !NEXT_PROC! starting: Call start at !time!"
    2>nul del %LOCK_FILES%.!NEXT_PROC!
    start /B "" cmd /C 9>"%LOCK_FILES%.!NEXT_PROC!" !CURRENT_CMD! >nul
)
set "LAUNCH="
call:WaitForLock
setlocal disableDelayedExpansion

call:Log "Delete last Log files"
2>nul del %LOCK_FILES%.*

echo.
call:EchoAndLog "Backup done........"
echo.
echo.
pause
exit 0

:EXIT_1
call:EchoAndLog "Date can not be computed exit with code 1"
echo.
echo.
pause
exit 1

:EXIT_2
call:EchoAndLog "WinRar not found exit with rc 2"
echo.
echo.
pause
exit 2

:EXIT_3
call:EchoAndLog "%INFILE% not found exit with rc 2"
echo.
echo.
pause
exit 3

:EXIT_4
call:EchoAndLog "%EXCLUDE_FILE% not found exit with rc 2"
echo.
echo.
pause
exit 4

goto:eof

:WaitForLock 
	for /l %%N in (1 1 %PROCESS_START_COUNTER%) do 2>nul (
		REM call:Log "check lock for process %%N"
		if not defined END_PROC%%N (
			REM call:Log "Proc %%N not finished"
			if exist "%LOCK_FILES%.%%N" (
				REM call:Log "%LOCK_FILES%.%%N exists"
				
				9>>"%LOCK_FILES%.%%N" (
					echo. Process %%N finished
					call:Log "   process %%N finished: Could acquire lock at !time!"
					if defined launch (
						set "NEXT_PROC=%%N"
						exit /b
					)
					set /a "PROCESS_END_COUNTER+=1"
					set "END_PROC%%N=1"
				) 
				timeout /T 1 > nul
			)
		)
	)
	if %PROCESS_END_COUNTER% lss %PROCESS_START_COUNTER% (
		goto :WaitForLock
	)
goto:eof

:RetentionRemoval
	set fileName=%~1
	call:Log " Current File: %fileName%" 
	set mod_mm=%fileName:~5,2%
	set mod_yy=%fileName:~0,4%
	call:Log "  mod_mm:      %mod_mm%"				
	call:Log "  mod_yy:      %mod_yy%"	

	if %mod_yy% LSS %YEAR_O% ( 
		call:Log "  Delete because of year" 
		GOTO :REMOVE_FILE 
	) 
	if %mod_yy% EQU %YEAR_O% ( 
		if %mod_mm% LEQ %MONTH_O% ( 
			call:Log "  Delete because of month" 
			GOTO :REMOVE_FILE 
		) 
	)
	call:Log "  Too young to be removed"
	GOTO :NEXT_FILE
	
	:REMOVE_FILE
		call:EchoAndLog "  %fileName% will be deleted, as it is older than %RETENTION% month."
		call:Log "  calling: del %fileName%"
		set NOTHING_DELETED=N
		del "%fileName%" >> "%LOGFILE%"
	:NEXT_FILE
goto:eof

:EchoAndLog
	echo %~1
	echo %~1 >>"%LOGFILE%"
goto:eof

:Log
	echo %~1 >>"%LOGFILE%"
goto:eof
