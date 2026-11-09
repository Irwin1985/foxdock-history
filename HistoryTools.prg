*==================================================================
* HistoryTools.prg: las tools del plugin «history» para el agente.
*
* Heredan de IdeTool (plugins\foxagent\IdeTools.prg): el host, J(), Done(),
* los parámetros y el rol. Por eso el plugin solo las da cuando IdeTools.prg ya
* está en SET PROCEDURE, que es cuando foxagent pide las tools.
*
*   ide_history_list     las versiones de un fichero (lee)
*   ide_history_diff     el diff de una versión contra el fichero (lee)
*   ide_history_restore  restaura una versión (actúa: rol 10); se niega
*                        con el diseñador abierto, como el botón
*
* Superficie pública en inglés. Fichero en CP1252.
*==================================================================

#DEFINE HS_NO_HOST "FoxDock is not mounted (after CLEAR ALL it sleeps until a FoxDock menu bar or key is pressed)"
#DEFINE HS_NO_PLUGIN "FoxDock's history plugin is not loaded, so there is no history to read."
#DEFINE HS_FILE_DESC "The binary: its path, or its name if only one file with history has that name (for example customer.scx)."

DEFINE CLASS IdeHistoryTool AS IdeTool
	*-- El plugin history, o .NULL.
	PROCEDURE History
		IF ISNULL(THIS.Host())
			RETURN .NULL.
		ENDIF
		RETURN _screen.oFoxDock.PluginById("history")
	ENDPROC

	*-- Lo de version.txt de una versión, como objeto JSON.
	PROCEDURE VersionObject
		LPARAMETERS toP, tcFile, tcVersion
		LOCAL loJ, loV, lcDir, lcText
		LOCAL ARRAY laF[1]
		loJ = THIS.J()
		lcDir = toP.FolderOf(tcFile) + tcVersion + "\"
		loV = loJ.MakeObject()
		loJ.Put(loV, "version", tcVersion)
		loJ.Put(loV, "taken", toP.InfoValue(lcDir, "taken"))
		loJ.Put(loV, "reason", toP.InfoValue(lcDir, "reason"))
		loJ.Put(loV, "binarySize", IIF(ADIR(laF, lcDir + JUSTFNAME(tcFile)) > 0, laF[1, 2], 0))
		loJ.Put(loV, "memoSize", IIF(ADIR(laF, lcDir + JUSTFNAME(toP.MemoOf(tcFile))) > 0, laF[1, 2], 0))
		lcText = toP.TextNameOf(lcDir + JUSTFNAME(tcFile))
		loJ.Put(loV, "text", toP.InfoValue(lcDir, "text"))
		loJ.Put(loV, "textFile", IIF(FILE(lcText), lcText, .NULL.))
		loJ.Put(loV, "folder", lcDir)
		RETURN loV
	ENDPROC
ENDDEFINE


DEFINE CLASS IdeHistoryListTool AS IdeHistoryTool
	ToolName = "ide_history_list"
	ToolDescription = "The versions FoxDock's history plugin keeps of a Visual FoxPro binary (.scx, .vcx, .frx, .lbx, .mnx), " + ;
		"newest first: each with its name (version, yyyymmdd-hhmmss), when and why it was taken, the sizes of the binary and " + ;
		"its memo, and its FoxBin2Prg text (text says what happened to it; textFile is its path, or null). The newest is " + ;
		"what is on disk after the last edit. Reads only."

	FUNCTION DefineParameters()
		THIS.AddParam("file", "string", HS_FILE_DESC, .T.)
	ENDFUNC

	FUNCTION Run(toContext)
		LOCAL loP, loJ, loD, loList, lcFile, lcWhy, lnN, lnI
		LOCAL ARRAY laV[1]
		IF ISNULL(THIS.Host())
			RETURN THIS.Err(HS_NO_HOST)
		ENDIF
		loP = THIS.History()
		IF ISNULL(loP)
			RETURN THIS.Err(HS_NO_PLUGIN)
		ENDIF
		lcWhy = ""
		lcFile = loP.FindFile(THIS.PText(toContext, "file"), @lcWhy)
		IF EMPTY(lcFile)
			RETURN THIS.Err(lcWhy)
		ENDIF
		loJ = THIS.J()
		loD = loJ.MakeObject()
		loJ.Put(loD, "file", lcFile)
		loJ.Put(loD, "folder", loP.FolderOf(lcFile))
		lnN = loP.Versions(lcFile, @laV)
		loJ.Put(loD, "count", lnN)
		loList = loJ.MakeArray()
		FOR lnI = lnN TO 1 STEP -1
			loList.Add(THIS.VersionObject(loP, lcFile, laV[lnI]))
		ENDFOR
		loJ.Put(loD, "versions", loList)
		RETURN THIS.Done(loD)
	ENDFUNC
ENDDEFINE


DEFINE CLASS IdeHistoryDiffTool AS IdeHistoryTool
	ToolName = "ide_history_diff"
	ToolDescription = "The differences, line by line, between the FoxBin2Prg text of one saved version of a Visual FoxPro " + ;
		"binary and the file as it is now ('- ' removed, '+ ' added, 3 lines of context, with line numbers). If the file is " + ;
		"locked by its designer, against the newest version, and 'against' says so. Needs the version's text (FoxKit); " + ;
		"without it, it says so. Reads only; changes nothing."

	FUNCTION DefineParameters()
		THIS.AddParam("file", "string", HS_FILE_DESC, .T.)
		THIS.AddParam("version", "string", "The version, as ide_history_list gives it (yyyymmdd-hhmmss).", .T.)
	ENDFUNC

	FUNCTION Run(toContext)
		LOCAL loP, loJ, loD, lcFile, lcWhy, lcVersion, lcDiff
		IF ISNULL(THIS.Host())
			RETURN THIS.Err(HS_NO_HOST)
		ENDIF
		loP = THIS.History()
		IF ISNULL(loP)
			RETURN THIS.Err(HS_NO_PLUGIN)
		ENDIF
		lcWhy = ""
		lcFile = loP.FindFile(THIS.PText(toContext, "file"), @lcWhy)
		IF EMPTY(lcFile)
			RETURN THIS.Err(lcWhy)
		ENDIF
		lcVersion = LOWER(THIS.PText(toContext, "version"))
		IF EMPTY(lcVersion)
			RETURN THIS.Err("'version' is required: one of the names ide_history_list gives (yyyymmdd-hhmmss).")
		ENDIF
		lcDiff = loP.Diff(lcFile, lcVersion, @lcWhy)
		IF EMPTY(lcDiff)
			RETURN THIS.Err(lcWhy)
		ENDIF
		loJ = THIS.J()
		loD = loJ.MakeObject()
		loJ.Put(loD, "file", lcFile)
		loJ.Put(loD, "version", lcVersion)
		*-- STREXTRACT y no MLINE: MLINE corta en SET MEMOWIDTH.
		loJ.Put(loD, "against", STREXTRACT(lcDiff, "+++ ", CHR(13)))
		loJ.Put(loD, "diff", lcDiff)
		RETURN THIS.Done(loD)
	ENDFUNC
ENDDEFINE


DEFINE CLASS IdeHistoryRestoreTool AS IdeHistoryTool
	ToolName = "ide_history_restore"
	lActsOnIde = .T.
	ToolDescription = "Restores a saved version of a Visual FoxPro binary over the file: the binary AND its memo, never one " + ;
		"without the other. First it keeps the current state as a new version (returned in 'before'), so a restore is undone " + ;
		"by restoring that one. It refuses while a designer has the file open (close it first), and says so."

	FUNCTION DefineParameters()
		THIS.AddParam("file", "string", HS_FILE_DESC, .T.)
		THIS.AddParam("version", "string", "The version to restore, as ide_history_list gives it (yyyymmdd-hhmmss).", .T.)
	ENDFUNC

	FUNCTION Run(toContext)
		LOCAL loP, loJ, loD, lcFile, lcWhy, lcVersion
		IF ISNULL(THIS.Host())
			RETURN THIS.Err(HS_NO_HOST)
		ENDIF
		loP = THIS.History()
		IF ISNULL(loP)
			RETURN THIS.Err(HS_NO_PLUGIN)
		ENDIF
		lcWhy = ""
		lcFile = loP.FindFile(THIS.PText(toContext, "file"), @lcWhy)
		IF EMPTY(lcFile)
			RETURN THIS.Err(lcWhy)
		ENDIF
		lcVersion = LOWER(THIS.PText(toContext, "version"))
		IF EMPTY(lcVersion)
			RETURN THIS.Err("'version' is required: one of the names ide_history_list gives (yyyymmdd-hhmmss).")
		ENDIF
		lcWhy = loP.Restore(lcFile, lcVersion)
		IF !EMPTY(lcWhy)
			RETURN THIS.Err(lcWhy)
		ENDIF
		_screen.oFoxDock.AgentDid("restored " + JUSTFNAME(lcFile) + " to version " + lcVersion + " (the state before is version " + loP.cLastNote + ")")
		loJ = THIS.J()
		loD = loJ.MakeObject()
		loJ.Put(loD, "file", lcFile)
		loJ.Put(loD, "restored", lcVersion)
		loJ.Put(loD, "before", loP.cLastNote)
		RETURN THIS.Done(loD)
	ENDFUNC
ENDDEFINE
