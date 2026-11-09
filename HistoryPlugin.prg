*==================================================================
* HistoryPlugin.prg: el plugin «history» de FoxDock.
*
* Cada binario de VFP que se edita deja su versión anterior: el binario Y su
* memo (nunca uno sin el otro) y, si está FoxKit, su texto de
* FoxBin2Prg (vfp2text bin2prg), para poder enseñar un diff.
*
* Qué vigila: .scx, .vcx, .frx, .lbx y .mnx (con su .sct, .vct, .frt, .lbt y
* .mnt). El .pjx no, porque cambia a cada rato; la opción history.extensions
* cambia la lista.
*
* Cuándo toma la versión:
*   - Desde el Project Manager (OnQueryModifyFile), ANTES de que se abra el
*     diseñador: el fichero todavía se puede copiar, y se copia.
*   - Con un MODIFY FORM tecleado, que no pasa por el hook, FoxDock se
*     entera cuando aparece la ventana «Form Designer - x.scx» (OnWindowOpen).
*     Para entonces el diseñador TIENE EL FICHERO BLOQUEADO: COPY FILE da el
*     error 3, FILETOSTR el 1705 y USE AGAIN SHARED el 3. Lo que sí se ve es su
*     tamaño, fecha y hora (ADIR). Si la versión más nueva tiene los mismos, esa
*     es la anterior y no hace falta copiar nada; si no, la anterior se ha
*     perdido, y el log lo dice.
*   - Al cerrar el diseñador (OnWindowClose, o en OnIdle en cuanto el fichero
*     se deja abrir otra vez): si no cambió, la versión que se tomó al abrir se
*     descarta (abrir y cerrar sin tocar no llena el historial); si cambió, se
*     toma una versión del estado nuevo, con su texto. Así la más nueva es
*     siempre lo que hay en disco, y el diff de las dos últimas es el cambio.
*
* El texto (vfp2text bin2prg) se hace sin esperarlo: version.txt se escribe
* antes, con «text=being made», y TextStep lo anota al acabar. Un formulario
* con 1,5 MB de memo puede tardar más de 30 s, y con un tope fijo la versión
* se quedaría sin version.txt. El tope crece con el tamaño (TextTimeout).
* Solo se espera al texto cuando se pide un diff.
*
* Dónde: <DataDir>\history\<carpeta del fichero, legible>\<fichero>\
* <yyyymmdd-hhmmss>\, con el binario, el memo, el texto y version.txt (qué
* fichero, cuándo, por qué, tamaño, fecha y hora, y qué pasó con el texto).
*
* Restore copia el binario y el memo de una versión sobre el fichero, solo si
* ningún diseñador lo tiene abierto, y antes toma una versión del estado que
* pisa: restaurar es un cambio más y se deshace igual.
*
* Sin MESSAGEBOX: la confirmación es el botón, y el log y Notify dicen lo que
* se hizo. Toda escritura va con SET SAFETY OFF y se repone (un COPY FILE con
* SET SAFETY ON pregunta).
*
* Opciones (config.json, "options": { "history": { ... } }):
*   extensions    "scx,vcx,frx,lbx,mnx" por defecto
*   maxVersions   20 por defecto: por fichero; se borra la más vieja
*   baseline      .T. por defecto: al abrir un proyecto, sus binarios sin una
*                 versión con su tamaño, fecha y hora se copian (tres por tick,
*                 sin texto: se saca al pedir un diff). Cierra el hueco del
*                 MODIFY FORM tecleado para lo que está en un proyecto.
*   vfp2text      la ruta de vfp2text.exe, solo para la suite (una inventada
*                 simula que FoxKit no está). Sin ella, la de FoxKit en
*                 HKLM\SOFTWARE\irwinrodriguez.dev\FoxKit\InstallDir.
*
* nOrder 970: detrás de foxagent (960), sin cambiar el orden de los de antes.
*
* Fichero en CP1252, con los acentos escritos.
*==================================================================

#DEFINE CRLF CHR(13) + CHR(10)
#DEFINE HS_KINDS "Form,Class,Report,Label,Menu"
#DEFINE HS_TEXT_BASE 30
#DEFINE HS_TEXT_PER_MB 30
#DEFINE HS_TEXT_MAX 600
#DEFINE HS_TEXT_PENDING "pending (baseline: it is made when a diff asks for it)"
#DEFINE HS_TEXT_MAKING "being made (vfp2text is running)"
#DEFINE HS_TICK_BUDGET 0.1
#DEFINE HS_COPIES_PER_TICK 3

DEFINE CLASS HistoryPlugin AS PluginBase
	cId = "history"
	cTitle = "History"
	nOrder = 950
	cVersion = "0.1.0"
	lWantsIdle = .T.

	cRoot = ""            && <DataDir>\history\
	cExts = ""            && ",scx,vcx,frx,lbx,mnx,"
	nMax = 20
	cVfp2Text = ""        && vfp2text.exe, o "" si no se encontró
	cVfp2TextFrom = ""
	oOpen = .NULL.        && los ficheros en edición, clave UPPER(ruta)
	oSettle = .NULL.      && las ediciones cerradas «sin cambios» que se miran unos segundos más
	nSettle = 3           && history.settleSeconds
	oForm = .NULL.        && la lista de versiones (modeless)
	lLastNew = .F.        && la última TakeVersion creó una versión nueva
	cLastNote = ""
	lBaseline = .T.       && history.baseline: la línea base al abrir un proyecto
	oBaseQueue = .NULL.   && los binarios del proyecto por copiar, de tres en tres
	oTextJobs = .NULL.    && los textos en marcha, clave UPPER(carpeta de la versión)
	nBaseCopied = 0
	nBaseHad = 0
	nBaseSkipped = 0

	PROCEDURE Init
		LPARAMETERS toHost
		DODEFAULT(toHost)
		This.cRoot = ADDBS(toHost.DataDir) + "history\"
		This.cExts = "," + LOWER(CHRTRAN(TRANSFORM(toHost.Options.Get(This.cId, "extensions", "scx,vcx,frx,lbx,mnx")), " .", "")) + ","
		This.nMax = MAX(1, INT(VAL(TRANSFORM(toHost.Options.Get(This.cId, "maxVersions", 20)))))
		This.oOpen = CREATEOBJECT("Collection")
		This.oSettle = CREATEOBJECT("Collection")
		This.nSettle = MAX(0, VAL(TRANSFORM(toHost.Options.Get(This.cId, "settleSeconds", 3))))
		This.oBaseQueue = CREATEOBJECT("Collection")
		This.oTextJobs = CREATEOBJECT("Collection")
		This.lBaseline = toHost.Options.Get(This.cId, "baseline", .T.)
		This.FindVfp2Text()
		This.SweepTemp()
	ENDPROC

	*-- Los textos, en el idioma de FoxDock (HistoryStrings.prg).
	PROCEDURE BuildMenu
		LPARAMETERS toMenu
		This.cTitle = This.oHost.Translate("history.title")
		toMenu.AddBar(This.oHost.Translate("history.bar.show"), "ShowHistory", This.oHost.Translate("history.bar.show.message"))
		toMenu.AddBar(This.oHost.Translate("history.bar.folder"), "OpenFolder", This.oHost.Translate("history.bar.folder.message"))
		*-- El host vuelve a llamar a BuildMenu al cambiar de idioma;
		*-- la ventana abierta vuelve a poner sus textos.
		IF VARTYPE(This.oForm) == "O" AND !ISNULL(This.oForm)
			This.oForm.Texts()
		ENDIF
	ENDPROC

	*-- Las tools del agente: HistoryTools.prg, que hereda de IdeTool (el
	*-- IdeTools.prg del plugin foxagent, que ya está en SET PROCEDURE cuando
	*-- foxagent pide las tools).
	PROCEDURE GetAgentTools
		LPARAMETERS toTools
		IF !("\IDETOOLS." $ UPPER(SET("PROCEDURE")))
			RETURN 0
		ENDIF
		This.EnsureProcedures()
		toTools.Add(CREATEOBJECT("IdeHistoryListTool"))
		toTools.Add(CREATEOBJECT("IdeHistoryDiffTool"))
		toTools.Add(CREATEOBJECT("IdeHistoryRestoreTool"))
		RETURN 3
	ENDPROC

	PROCEDURE EnsureProcedures
		LOCAL lcTools, loErr
		lcTools = This.CodeFile("HistoryTools.prg")
		IF !EMPTY(This.cHome) AND !("\HISTORYTOOLS." $ UPPER(SET("PROCEDURE"))) AND FILE(lcTools)
			TRY
				SET PROCEDURE TO (lcTools) ADDITIVE
			CATCH TO loErr
				This.oHost.LogWarn("history: " + lcTools + " not loaded: " + loErr.Message)
			ENDTRY
		ENDIF
	ENDPROC

	*==============================================================
	* Los ganchos.
	*==============================================================

	*-- Desde el Project Manager: antes de abrir, el fichero se puede copiar.
	PROCEDURE OnQueryModifyFile
		LPARAMETERS toProject, toFile, tcClassName
		IF VARTYPE(toFile) == "O" AND This.Watches(toFile.Name)
			This.Begin(toFile.Name, "before editing (Project Manager)")
		ENDIF
		RETURN .T.
	ENDPROC

	PROCEDURE OnWindowOpen
		LPARAMETERS toInfo
		LOCAL lcName, lcFile
		lcName = This.DesignedName(toInfo.title)
		IF EMPTY(lcName) OR !This.Watches(lcName)
			RETURN .T.
		ENDIF
		lcFile = This.Resolve(lcName, toInfo.title)
		IF EMPTY(lcFile)
			This.oHost.Log("history: " + toInfo.title + ": " + lcName + " is not in an open project nor in SET PATH; no version taken")
			RETURN .T.
		ENDIF
		This.BeginLocked(lcFile, toInfo.title)
		RETURN .T.
	ENDPROC

	PROCEDURE OnWindowClose
		LPARAMETERS toInfo
		LOCAL lcName, lnI, loE
		lcName = This.DesignedName(toInfo.title)
		IF EMPTY(lcName)
			RETURN .T.
		ENDIF
		FOR lnI = This.oOpen.Count TO 1 STEP -1
			loE = This.oOpen.Item(lnI)
			IF loE.cTitle == toInfo.title OR (EMPTY(loE.cTitle) AND LOWER(JUSTFNAME(loE.cFile)) == LOWER(lcName))
				This.Finish(lnI)
			ENDIF
		ENDFOR
		RETURN .T.
	ENDPROC

	*-- La línea base: al abrir un proyecto, sus binarios vigilados
	*-- que no tengan una versión con su tamaño, fecha y hora se encolan, y
	*-- OnIdle los copia de tres en tres, sin texto. Así un MODIFY FORM tecleado
	*-- después (el diseñador lo bloquea) ya tiene su «antes».
	PROCEDURE OnProjectOpen
		LPARAMETERS toProject
		LOCAL loF, lnAdded, loErr
		IF !This.lBaseline OR VARTYPE(toProject) # "O"
			RETURN .T.
		ENDIF
		IF This.oBaseQueue.Count = 0
			This.nBaseCopied = 0
			This.nBaseHad = 0
			This.nBaseSkipped = 0
		ENDIF
		lnAdded = 0
		TRY
			FOR EACH loF IN toProject.Files
				IF This.Watches(loF.Name) AND This.oBaseQueue.GetKey(UPPER(loF.Name)) = 0
					This.oBaseQueue.Add(loF.Name, UPPER(loF.Name))
					lnAdded = lnAdded + 1
				ENDIF
			ENDFOR
		CATCH TO loErr
			This.oHost.LogWarn("history: baseline of " + toProject.Name + ": " + loErr.Message)
		ENDTRY
		IF lnAdded > 0
			This.oHost.Log("history: baseline: " + TRANSFORM(lnAdded) + " file(s) of " + JUSTFNAME(toProject.Name) + " to check")
		ENDIF
		RETURN .T.
	ENDPROC

	*-- Por tick, lo que quepa en HS_TICK_BUDGET segundos, y como mucho
	*-- HS_COPIES_PER_TICK copias: comprobar un binario que ya tiene su versión
	*-- es barato, y copiar no: si se limitaran también las comprobaciones,
	*-- abrir otra vez un proyecto grande (más de mil binarios) tardaría lo
	*-- mismo que la primera vez. Un fichero en uso se salta y se reintenta en
	*-- la siguiente apertura del proyecto.
	PROCEDURE BaselineStep
		LOCAL lcFile, lnN, lnT0, lnCopies
		LOCAL ARRAY laV[1]
		IF This.oBaseQueue.Count = 0
			RETURN
		ENDIF
		lnT0 = SECONDS()
		lnCopies = 0
		DO WHILE This.oBaseQueue.Count > 0
			lcFile = This.oBaseQueue.Item(1)
			This.oBaseQueue.Remove(1)
			DO CASE
				CASE !FILE(lcFile) OR !FILE(This.MemoOf(lcFile))
					This.nBaseSkipped = This.nBaseSkipped + 1
					This.oHost.Log("history: baseline: " + lcFile + " or its memo is not on disk; skipped")
				CASE This.IsLocked(lcFile)
					*-- Bloqueado no quiere decir en un diseñador: una librería de
					*-- clases la bloquea también el formulario que la usa.
					This.nBaseSkipped = This.nBaseSkipped + 1
					This.oHost.Log("history: baseline: " + lcFile + " is in use (open in a designer, or used by something " + ;
						"that is, like the class library of a form in its designer); skipped, it is retried at the next project open")
				OTHERWISE
					lnN = This.Versions(lcFile, @laV)
					IF lnN > 0 AND This.InfoValue(This.FolderOf(lcFile) + laV[lnN] + "\", "stamp") == This.Stamp(lcFile)
						This.nBaseHad = This.nBaseHad + 1
					ELSE
						IF EMPTY(This.TakeVersion(lcFile, "baseline", .T.))
							This.nBaseSkipped = This.nBaseSkipped + 1
						ELSE
							This.nBaseCopied = This.nBaseCopied + IIF(This.lLastNew, 1, 0)
							This.nBaseHad = This.nBaseHad + IIF(This.lLastNew, 0, 1)
							lnCopies = lnCopies + IIF(This.lLastNew, 1, 0)
						ENDIF
					ENDIF
			ENDCASE
			IF lnCopies >= HS_COPIES_PER_TICK OR ABS(SECONDS() - lnT0) >= HS_TICK_BUDGET
				EXIT
			ENDIF
		ENDDO
		IF This.oBaseQueue.Count = 0
			This.oHost.Log("history: baseline: " + TRANSFORM(This.nBaseCopied) + " files copied, " + ;
				TRANSFORM(This.nBaseHad) + " already had a version" + ;
				IIF(This.nBaseSkipped > 0, ", " + TRANSFORM(This.nBaseSkipped) + " skipped", ""))
		ENDIF
	ENDPROC

	*-- Sin FLL no llegan las ventanas: el cierre se nota porque el fichero se
	*-- deja abrir otra vez. Solo después de haberlo visto bloqueado, o pasados
	*-- 10 s (se abrió el hook y no llegó a abrirse el diseñador).
	PROCEDURE OnIdle
		LOCAL lnI, loE
		This.EnsureProcedures()
		This.TextStep()
		This.BaselineStep()
		This.SettleStep()
		FOR lnI = This.oOpen.Count TO 1 STEP -1
			loE = This.oOpen.Item(lnI)
			IF This.IsLocked(loE.cFile)
				loE.lSeenLocked = .T.
			ELSE
				IF loE.lSeenLocked OR SECONDS() - loE.nT0 > 10 OR SECONDS() < loE.nT0
					This.Finish(lnI)
				ENDIF
			ENDIF
		ENDFOR
	ENDPROC

	*==============================================================
	* Abrir y cerrar una edición.
	*==============================================================

	*-- El fichero se puede leer: se toma la versión.
	PROCEDURE Begin
		LPARAMETERS tcFile, tcReason
		LOCAL lcKey, lcV, loE
		lcKey = UPPER(tcFile)
		This.Unsettle(lcKey)
		IF This.oOpen.GetKey(lcKey) > 0
			*-- No se encadena sobre el resultado de Item(): VFP no lo navega.
			loE = This.oOpen.Item(lcKey)
			RETURN loE.cVersion
		ENDIF
		lcV = This.TakeVersion(tcFile, tcReason)
		loE = This.NewEdit(tcFile, lcV, This.lLastNew)
		This.oOpen.Add(loE, lcKey)
		RETURN lcV
	ENDPROC

	*-- El diseñador ya lo tiene bloqueado: solo se ve tamaño, fecha y hora.
	PROCEDURE BeginLocked
		LPARAMETERS tcFile, tcTitle
		LOCAL lcKey, loE, lnN, lcV, lnI, lcStamp
		LOCAL ARRAY laV[1]
		lcKey = UPPER(tcFile)
		This.Unsettle(lcKey)
		IF This.oOpen.GetKey(lcKey) > 0
			loE = This.oOpen.Item(lcKey)
			loE.cTitle = tcTitle
			loE.lSeenLocked = .T.
			RETURN
		ENDIF
		lcV = ""
		IF !This.IsLocked(tcFile)
			*-- Se pudo abrir (un diseñador que no lo bloquea): como el hook.
			lcV = This.TakeVersion(tcFile, "before editing (designer opened)")
			loE = This.NewEdit(tcFile, lcV, This.lLastNew)
		ELSE
			*-- La más nueva con el mismo tamaño, fecha y hora, aunque no sea la
			*-- más nueva de todas: tras un Restore, el fichero tiene el sello de
			*-- una vieja y la más nueva es «before restoring».
			lnN = This.Versions(tcFile, @laV)
			lcStamp = This.Stamp(tcFile)
			FOR lnI = lnN TO 1 STEP -1
				IF This.InfoValue(This.FolderOf(tcFile) + laV[lnI] + "\", "stamp") == lcStamp
					lcV = laV[lnI]
					EXIT
				ENDIF
			ENDFOR
			IF !EMPTY(lcV)
				This.oHost.Log("history: " + tcFile + " opened in its designer; the version before it is " + lcV + " (same size, date and time)")
			ELSE
				This.oHost.LogWarn("history: " + tcFile + " was opened in its designer before FoxDock could copy it (a typed " + ;
					"MODIFY, not from the Project Manager), and the designer locks it: its state before this edit could not be " + ;
					"kept (no saved version has its size, date and time). The state after the edit will be kept when the designer closes.")
			ENDIF
			loE = This.NewEdit(tcFile, lcV, .F.)
			loE.lSeenLocked = .T.
		ENDIF
		loE.cTitle = tcTitle
		This.oOpen.Add(loE, lcKey)
	ENDPROC

	PROTECTED PROCEDURE NewEdit
		LPARAMETERS tcFile, tcVersion, tlNew
		LOCAL loE
		loE = CREATEOBJECT("Empty")
		ADDPROPERTY(loE, "cFile", tcFile)
		ADDPROPERTY(loE, "cVersion", tcVersion)
		ADDPROPERTY(loE, "lNew", tlNew)
		ADDPROPERTY(loE, "cStamp", This.Stamp(tcFile))
		ADDPROPERTY(loE, "cTitle", "")
		ADDPROPERTY(loE, "nT0", SECONDS())
		ADDPROPERTY(loE, "lSeenLocked", .F.)
		RETURN loE
	ENDPROC

	*-- Se cerró la edición: con cambios, se toma una versión del estado nuevo.
	*-- Sin cambios todavía NO se decide: el diseñador puede no haber
	*-- escrito aún lo que guardó cuando llega su cierre (la versión
	*-- «after editing» saldría igual a la de antes, y el .sct del disco
	*-- tiene el cambio poco después). La edición pasa a oSettle y SettleStep la
	*-- vuelve a mirar en cada tick, hasta history.settleSeconds (3 por defecto).
	*-- Por ticks y sin esperas aquí.
	PROCEDURE Finish
		LPARAMETERS tnIndex
		LOCAL loE
		loE = This.oOpen.Item(tnIndex)
		This.oOpen.Remove(tnIndex)
		IF !FILE(loE.cFile)
			RETURN
		ENDIF
		IF This.Changed(loE)
			This.TakeAfter(loE, "")
			RETURN
		ENDIF
		ADDPROPERTY(loE, "nClosed", SECONDS())
		This.Unsettle(UPPER(loE.cFile))
		This.oSettle.Add(loE, UPPER(loE.cFile))
	ENDPROC

	*-- ¿El fichero o su memo ya no son los de la versión de apertura? Sin
	*-- versión de apertura, por tamaño, fecha y hora.
	PROCEDURE Changed
		LPARAMETERS toE
		IF !EMPTY(toE.cVersion)
			RETURN !This.Same(toE.cFile, This.FolderOf(toE.cFile) + toE.cVersion + "\")
		ENDIF
		RETURN !(This.Stamp(toE.cFile) == toE.cStamp)
	ENDPROC

	PROTECTED PROCEDURE TakeAfter
		LPARAMETERS toE, tcNote
		LOCAL lcV
		lcV = This.TakeVersion(toE.cFile, "after editing")
		IF !EMPTY(lcV)
			This.oHost.Log("history: " + toE.cFile + " changed; its new state is version " + lcV + ;
				IIF(EMPTY(toE.cVersion), "", ", the one before it " + toE.cVersion) + tcNote)
		ENDIF
	ENDPROC

	*-- Las ediciones cerradas sin cambios aún: en cuanto el fichero o su memo
	*-- cambian, la versión «after editing»; pasado history.settleSeconds sin
	*-- cambio, lo de siempre: la versión de apertura, si era nueva, se descarta.
	PROCEDURE SettleStep
		LOCAL lnI, loE, lnMs
		FOR lnI = This.oSettle.Count TO 1 STEP -1
			loE = This.oSettle.Item(lnI)
			lnMs = INT(1000 * MAX(0, SECONDS() - loE.nClosed))
			DO CASE
				CASE !FILE(loE.cFile)
					This.oSettle.Remove(lnI)
				CASE This.Changed(loE)
					This.oSettle.Remove(lnI)
					This.TakeAfter(loE, " (settled after " + TRANSFORM(lnMs) + " ms)")
				CASE lnMs >= 1000 * This.nSettle OR SECONDS() < loE.nClosed
					This.oSettle.Remove(lnI)
					IF loE.lNew
						This.Discard(loE.cFile, loE.cVersion)
						This.oHost.Log("history: " + loE.cFile + " closed without changes (settled); version " + ;
							loE.cVersion + " discarded")
					ELSE
						This.oHost.Log("history: " + loE.cFile + " closed without changes (settled)")
					ENDIF
			ENDCASE
		ENDFOR
	ENDPROC

	*-- Un fichero que se vuelve a abrir sale de la lista sin tomar nada: ya
	*-- tiene (o va a tener) su entrada en oOpen.
	PROCEDURE Unsettle
		LPARAMETERS tcKey
		IF This.oSettle.GetKey(tcKey) > 0
			This.oSettle.Remove(tcKey)
		ENDIF
	ENDPROC

	*==============================================================
	* Las versiones.
	*==============================================================

	PROCEDURE Watches
		LPARAMETERS tcFile
		RETURN !EMPTY(tcFile) AND ("," + LOWER(JUSTEXT(tcFile)) + ",") $ This.cExts AND !EMPTY(This.MemoOf(tcFile))
	ENDPROC

	PROCEDURE MemoOf
		LPARAMETERS tcFile
		LOCAL lcExt, lcMemo
		lcExt = LOWER(JUSTEXT(tcFile))
		lcMemo = ICASE(lcExt == "scx", "sct", lcExt == "vcx", "vct", lcExt == "frx", "frt", lcExt == "lbx", "lbt", ;
			lcExt == "mnx", "mnt", lcExt == "pjx", "pjt", "")
		RETURN IIF(EMPTY(lcMemo), "", FORCEEXT(tcFile, lcMemo))
	ENDPROC

	*-- <raíz>\<carpeta del fichero, legible>\<fichero>\. La carpeta es su ruta
	*-- sin los dos puntos y con guiones: c:\proj\forms -> c-proj-forms. Si pasa
	*-- de 80 letras se recorta por el medio y lleva su suma, para seguir siendo
	*-- única.
	PROCEDURE FolderOf
		LPARAMETERS tcFile
		LOCAL lcDir, lcName
		lcDir = LOWER(JUSTPATH(FULLPATH(tcFile)))
		lcName = CHRTRAN(STRTRAN(lcDir, ":", ""), "\/", "--")
		IF LEN(lcName) > 80
			lcName = LEFT(lcName, 40) + "~" + RIGHT(lcName, 30) + "~" + SYS(2007, lcDir)
		ENDIF
		RETURN This.cRoot + lcName + "\" + LOWER(JUSTFNAME(tcFile)) + "\"
	ENDPROC

	*-- Las versiones de un fichero, de la más vieja a la más nueva.
	PROCEDURE Versions
		LPARAMETERS tcFile, taV
		LOCAL lcDir, lnN, lnI, lnK
		LOCAL ARRAY laD[1]
		lcDir = This.FolderOf(tcFile)
		lnK = 0
		DIMENSION taV[1]
		taV[1] = ""
		IF !DIRECTORY(lcDir, 1)
			RETURN 0
		ENDIF
		lnN = ADIR(laD, lcDir + "*.*", "D")
		FOR lnI = 1 TO lnN
			IF "D" $ laD[lnI, 5] AND ISDIGIT(laD[lnI, 1]) AND LEN(laD[lnI, 1]) >= 15 AND FILE(lcDir + laD[lnI, 1] + "\version.txt")
				lnK = lnK + 1
				DIMENSION taV[lnK]
				taV[lnK] = LOWER(laD[lnI, 1])
			ENDIF
		ENDFOR
		IF lnK > 1
			=ASORT(taV)
		ENDIF
		RETURN lnK
	ENDPROC

	*-- Tamaño, fecha y hora del binario y del memo (ADIR: se ve aunque el
	*-- diseñador lo tenga bloqueado).
	PROCEDURE Stamp
		LPARAMETERS tcFile
		RETURN This.StampOf(tcFile) + ";" + This.StampOf(This.MemoOf(tcFile))
	ENDPROC

	PROTECTED PROCEDURE StampOf
		LPARAMETERS tcFile
		LOCAL ARRAY laF[1]
		IF EMPTY(tcFile) OR ADIR(laF, tcFile) = 0
			RETURN "-"
		ENDIF
		RETURN TRANSFORM(laF[1, 2]) + "|" + DTOS(laF[1, 3]) + "|" + laF[1, 4]
	ENDPROC

	*-- ¿El fichero está bloqueado? FOPEN no da error: devuelve -1.
	PROCEDURE IsLocked
		LPARAMETERS tcFile
		LOCAL lnH
		lnH = FOPEN(tcFile, 0)
		IF lnH < 0
			RETURN FILE(tcFile)
		ENDIF
		=FCLOSE(lnH)
		RETURN .F.
	ENDPROC

	*-- ¿El fichero tiene los mismos bytes que esa versión (binario y memo)?
	PROCEDURE Same
		LPARAMETERS tcFile, tcVersionDir
		LOCAL lcMemo, llSame, loErr
		lcMemo = This.MemoOf(tcFile)
		llSame = .F.
		TRY
			llSame = FILETOSTR(tcFile) == FILETOSTR(tcVersionDir + JUSTFNAME(tcFile)) AND ;
				FILETOSTR(lcMemo) == FILETOSTR(tcVersionDir + JUSTFNAME(lcMemo))
		CATCH TO loErr
			llSame = .F.
		ENDTRY
		RETURN llSame
	ENDPROC

	*-- Toma una versión: el binario, el memo y su texto. Devuelve su nombre
	*-- (yyyymmdd-hhmmss), el de la más nueva si no hay nada nuevo, o "".
	PROCEDURE TakeVersion
		LPARAMETERS tcFile, tcReason, tlNoText
		LOCAL lcMemo, lcDir, lcV, lcBase, lnN, lnTry, lcSafety, lcTalk, loErr, llOk, lcText, lcStamp, lcFail, ltNow
		LOCAL ARRAY laV[1]
		This.lLastNew = .F.
		This.cLastNote = ""
		lcMemo = This.MemoOf(tcFile)
		IF !FILE(tcFile) OR EMPTY(lcMemo) OR !FILE(lcMemo)
			This.cLastNote = "no memo file"
			This.oHost.LogWarn("history: " + tcFile + " has no memo file next to it (" + JUSTFNAME(lcMemo) + ;
				"); no version taken: a binary is never kept without its memo")
			RETURN ""
		ENDIF
		lcDir = This.FolderOf(tcFile)
		lnN = This.Versions(tcFile, @laV)
		IF lnN > 0 AND This.Same(tcFile, lcDir + laV[lnN] + "\")
			This.cLastNote = "unchanged since version " + laV[lnN]
			RETURN laV[lnN]
		ENDIF
		lcStamp = This.Stamp(tcFile)
		*-- Una sola lectura del reloj: el nombre y «taken» dicen el mismo segundo.
		ltNow = DATETIME()
		lcBase = LEFT(TTOC(ltNow, 1), 8) + "-" + RIGHT(TTOC(ltNow, 1), 6)
		lcV = lcBase
		lnTry = 1
		DO WHILE DIRECTORY(lcDir + lcV, 1)
			lnTry = lnTry + 1
			lcV = lcBase + "-" + TRANSFORM(lnTry)
		ENDDO
		*-- SET TALK OFF: con el del IDE, COPY FILE escribe «N bytes copied.» en la
		*-- barra de estado.
		lcSafety = SET("SAFETY")
		lcTalk = SET("TALK")
		SET SAFETY OFF
		SET TALK OFF
		llOk = .F.
		lcFail = ""
		TRY
			This.MakeDirs(lcDir + lcV + "\")
			COPY FILE (tcFile) TO (lcDir + lcV + "\" + JUSTFNAME(tcFile))
			COPY FILE (lcMemo) TO (lcDir + lcV + "\" + JUSTFNAME(lcMemo))
			llOk = .T.
		CATCH TO loErr
			lcFail = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
		FINALLY
			SET TALK &lcTalk
			SET SAFETY &lcSafety
		ENDTRY
		IF !llOk
			This.RemoveDir(lcDir + lcV + "\")
			This.cLastNote = "could not copy: " + lcFail
			This.oHost.LogWarn("history: " + tcFile + ": no version taken, it could not be copied (" + lcFail + ")")
			RETURN ""
		ENDIF
		*-- version.txt va ANTES que el texto: una versión no se queda nunca sin él,
		*-- y sin él no se ve. La línea base va sin texto (se saca al pedir un
		*-- diff, EnsureText); las demás, con el texto en marcha y sin esperarlo
		*-- (StartText; TextStep lo anota al acabar).
		lcText = ICASE(tlNoText, HS_TEXT_PENDING, EMPTY(This.cVfp2Text), "none (FoxKit not installed)", HS_TEXT_MAKING)
		STRTOFILE("file=" + tcFile + CRLF + ;
			"taken=" + TTOC(ltNow, 3) + CRLF + ;
			"reason=" + tcReason + CRLF + ;
			"binary=" + JUSTFNAME(tcFile) + CRLF + ;
			"memo=" + JUSTFNAME(lcMemo) + CRLF + ;
			"stamp=" + lcStamp + CRLF + ;
			"text=" + lcText + CRLF, lcDir + lcV + "\version.txt")
		IF lcText == HS_TEXT_MAKING
			This.QueueText(lcDir + lcV + "\", JUSTFNAME(tcFile))
		ENDIF
		This.lLastNew = .T.
		*-- La línea base no lleva una línea por fichero: basta su resumen.
		IF !(tcReason == "baseline")
			This.oHost.Log("history: version " + lcV + " of " + tcFile + " (" + tcReason + "); text: " + lcText)
		ENDIF
		This.Prune(tcFile)
		RETURN lcV
	ENDPROC

	*-- El tope por fichero: se borra la más vieja.
	PROCEDURE Prune
		LPARAMETERS tcFile
		LOCAL lnN, lnI
		LOCAL ARRAY laV[1]
		lnN = This.Versions(tcFile, @laV)
		FOR lnI = 1 TO lnN - This.nMax
			This.Discard(tcFile, laV[lnI])
			This.oHost.Log("history: version " + laV[lnI] + " of " + tcFile + " removed (maxVersions " + TRANSFORM(This.nMax) + ")")
		ENDFOR
	ENDPROC

	*-- Con su texto en marcha no se puede borrar (vfp2text tiene sus ficheros
	*-- abiertos): deja de verse ya (sin version.txt no es una versión) y la
	*-- carpeta se borra cuando acabe (TextStep).
	PROCEDURE Discard
		LPARAMETERS tcFile, tcVersion
		LOCAL lcDir, loJob
		IF EMPTY(tcVersion)
			RETURN
		ENDIF
		lcDir = This.FolderOf(tcFile) + tcVersion + "\"
		IF This.oTextJobs.GetKey(UPPER(lcDir)) > 0
			loJob = This.oTextJobs.Item(UPPER(lcDir))
			loJob.lDiscard = .T.
			This.EraseQuietly(lcDir + "version.txt")
			RETURN
		ENDIF
		This.RemoveDir(lcDir)
	ENDPROC

	*-- Lo que dice version.txt de una clave ("" si no está).
	PROCEDURE InfoValue
		LPARAMETERS tcVersionDir, tcKey
		LOCAL lnN, lnI, lcLine
		LOCAL ARRAY laL[1]
		IF !FILE(tcVersionDir + "version.txt")
			RETURN ""
		ENDIF
		lnN = ALINES(laL, FILETOSTR(tcVersionDir + "version.txt"))
		FOR lnI = 1 TO lnN
			lcLine = laL[lnI]
			IF LOWER(LEFT(lcLine, LEN(tcKey) + 1)) == LOWER(tcKey) + "="
				RETURN SUBSTR(lcLine, LEN(tcKey) + 2)
			ENDIF
		ENDFOR
		RETURN ""
	ENDPROC

	*-- Los ficheros que tienen historial (la ruta, de version.txt).
	PROCEDURE Files
		LOCAL loAll, lnA, lnB, lnI, lnJ, lcA, lcB, lcFile, lnN
		LOCAL ARRAY laA[1], laB[1], laV[1]
		loAll = CREATEOBJECT("Collection")
		IF !DIRECTORY(This.cRoot, 1)
			RETURN loAll
		ENDIF
		lnA = ADIR(laA, This.cRoot + "*.*", "D")
		FOR lnI = 1 TO lnA
			lcA = laA[lnI, 1]
			IF !("D" $ laA[lnI, 5]) OR (lcA == "." OR lcA == "..")
				LOOP
			ENDIF
			lnB = ADIR(laB, This.cRoot + lcA + "\*.*", "D")
			FOR lnJ = 1 TO lnB
				lcB = laB[lnJ, 1]
				IF !("D" $ laB[lnJ, 5]) OR (lcB == "." OR lcB == "..")
					LOOP
				ENDIF
				lcFile = This.NewestFileOf(This.cRoot + lcA + "\" + lcB + "\")
				IF !EMPTY(lcFile) AND loAll.GetKey(UPPER(lcFile)) = 0
					loAll.Add(lcFile, UPPER(lcFile))
				ENDIF
			ENDFOR
		ENDFOR
		RETURN loAll
	ENDPROC

	PROTECTED PROCEDURE NewestFileOf
		LPARAMETERS tcDir
		LOCAL lnN, lnI, lcBest
		LOCAL ARRAY laD[1]
		lcBest = ""
		lnN = ADIR(laD, tcDir + "*.*", "D")
		FOR lnI = 1 TO lnN
			*-- EMPTY() aparte: con SET EXACT OFF, "x" = "" es .T., así que "x" > ""
			*-- es .F. y ninguna versión llegaría a ser la más nueva.
			IF "D" $ laD[lnI, 5] AND ISDIGIT(laD[lnI, 1]) AND FILE(tcDir + laD[lnI, 1] + "\version.txt") AND ;
					(EMPTY(lcBest) OR LOWER(laD[lnI, 1]) > lcBest)
				lcBest = LOWER(laD[lnI, 1])
			ENDIF
		ENDFOR
		RETURN IIF(EMPTY(lcBest), "", This.InfoValue(tcDir + lcBest + "\", "file"))
	ENDPROC

	*==============================================================
	* El texto (vfp2text bin2prg) y el diff.
	*==============================================================

	PROCEDURE FindVfp2Text
		LOCAL lcExe, loShell, loErr
		lcExe = TRANSFORM(This.oHost.Options.Get(This.cId, "vfp2text", ""))
		This.cVfp2TextFrom = "option history.vfp2text"
		IF EMPTY(lcExe)
			This.cVfp2TextFrom = "FoxKit (HKLM\SOFTWARE\irwinrodriguez.dev\FoxKit\InstallDir)"
			TRY
				loShell = CREATEOBJECT("WScript.Shell")
				lcExe = ADDBS(loShell.RegRead("HKLM\SOFTWARE\irwinrodriguez.dev\FoxKit\InstallDir")) + "vfp2text.exe"
			CATCH TO loErr
				lcExe = ""
			ENDTRY
		ENDIF
		This.cVfp2Text = IIF(!EMPTY(lcExe) AND FILE(lcExe), lcExe, "")
	ENDPROC

	*-- El texto de FoxBin2Prg de un binario (junto a él: FoxBin2Prg no deja
	*-- elegir la carpeta, y la extensión sale en mayúsculas), esperándolo.
	*-- Devuelve lo que se anota en version.txt.
	PROCEDURE MakeText
		LPARAMETERS tcBinary
		LOCAL loJob
		IF EMPTY(This.cVfp2Text)
			RETURN "none (FoxKit not installed)"
		ENDIF
		loJob = This.StartText(tcBinary)
		This.WaitText(loJob)
		RETURN loJob.cResult
	ENDPROC

	*-- El tope de vfp2text: 30 s, y 30 más por MB del binario y su memo, hasta
	*-- 10 minutos: un formulario con 1,5 MB de memo puede tardar más de 30 s.
	PROCEDURE TextTimeout
		LPARAMETERS tcBinary
		LOCAL lnBytes, lcMemo
		LOCAL ARRAY laF[1]
		lnBytes = 0
		IF ADIR(laF, tcBinary) > 0
			lnBytes = lnBytes + laF[1, 2]
		ENDIF
		lcMemo = This.MemoOf(tcBinary)
		IF !EMPTY(lcMemo) AND ADIR(laF, lcMemo) > 0
			lnBytes = lnBytes + laF[1, 2]
		ENDIF
		RETURN MIN(HS_TEXT_MAX, HS_TEXT_BASE + INT(HS_TEXT_PER_MB * lnBytes / 1048576))
	ENDPROC

	*-- demo.scx -> demo.SC2 (la extensión de FoxBin2Prg: la 3.ª letra es un 2).
	PROCEDURE TextNameOf
		LPARAMETERS tcBinary
		RETURN FORCEEXT(tcBinary, UPPER(LEFT(JUSTEXT(tcBinary), 2)) + "2")
	ENDPROC

	*-- vfp2text bin2prg, SIN ventana (WScript.Shell.Run con 0) y SIN esperar:
	*-- el cmd deja el código de salida en un fichero (cmd /v:on y !errorlevel!,
	*-- que se lee al acabar y no al empezar). Devuelve el trabajo, que recogen
	*-- PollText, WaitText o TextStep.
	PROCEDURE StartText
		LPARAMETERS tcBinary
		LOCAL lcTag, loJob, lcCmd, loShell, loErr
		lcTag = ADDBS(SYS(2023)) + "foxdock-history-" + SYS(2015)
		loJob = CREATEOBJECT("Empty")
		ADDPROPERTY(loJob, "cBinary", tcBinary)
		ADDPROPERTY(loJob, "cDir", ADDBS(JUSTPATH(tcBinary)))
		ADDPROPERTY(loJob, "cOut", lcTag + ".out")
		ADDPROPERTY(loJob, "cRc", lcTag + ".rc")
		ADDPROPERTY(loJob, "nT0", SECONDS())
		ADDPROPERTY(loJob, "nTimeout", This.TextTimeout(tcBinary))
		ADDPROPERTY(loJob, "cResult", "")
		ADDPROPERTY(loJob, "lDiscard", .F.)
		lcCmd = 'cmd /v:on /c ""' + This.cVfp2Text + '" bin2prg "' + tcBinary + '" --format json > "' + loJob.cOut + ;
			'" 2>&1 & echo !errorlevel! > "' + loJob.cRc + '""'
		TRY
			loShell = CREATEOBJECT("WScript.Shell")
			loShell.Run(lcCmd, 0, .F.)
		CATCH TO loErr
			loJob.cResult = "failed (vfp2text did not start: " + loErr.Message + ")"
		ENDTRY
		RETURN loJob
	ENDPROC

	*-- ¿Acabó? Deja en cResult lo que se anota en version.txt. Todo lo que lee va
	*-- en TRY: el .out puede seguir abierto por el cmd, y FILETOSTR da el 1705.
	*-- Lo que no se puede leer todavía se mira en el tick siguiente.
	PROCEDURE PollText
		LPARAMETERS toJob
		LOCAL lcRc, lcOut, loErr, llRead
		IF !EMPTY(toJob.cResult)
			RETURN .T.
		ENDIF
		IF FILE(toJob.cRc)
			llRead = .F.
			lcRc = ""
			lcOut = ""
			TRY
				lcRc = FILETOSTR(toJob.cRc)
				IF FILE(toJob.cOut)
					lcOut = STRCONV(FILETOSTR(toJob.cOut), 11)
				ENDIF
				llRead = !EMPTY(lcRc)
			CATCH TO loErr
				llRead = .F.
			ENDTRY
			IF llRead
				toJob.cResult = This.TextResult(toJob.cBinary, INT(VAL(lcRc)), lcOut)
				This.EraseQuietly(toJob.cOut)
				This.EraseQuietly(toJob.cRc)
				RETURN .T.
			ENDIF
		ENDIF
		IF ABS(SECONDS() - toJob.nT0) >= toJob.nTimeout
			*-- Sus ficheros siguen abiertos: los borra SweepTemp otro día.
			toJob.cResult = "failed (vfp2text did not finish in " + TRANSFORM(toJob.nTimeout) + " s)"
			RETURN .T.
		ENDIF
		RETURN .F.
	ENDPROC

	PROCEDURE TextResult
		LPARAMETERS tcBinary, tnRc, tcOut
		IF tnRc = 0 AND FILE(This.TextNameOf(tcBinary))
			RETURN JUSTFNAME(This.TextNameOf(tcBinary))
		ENDIF
		RETURN "failed (vfp2text exit " + TRANSFORM(tnRc) + ": " + LEFT(CHRTRAN(tcOut, CRLF, "  "), 200) + ")"
	ENDPROC

	*-- Espera a un trabajo (un diff que lo necesita). VFP no pinta mientras
	*-- tanto, así que la barra de estado dice antes cuánto puede tardar.
	PROCEDURE WaitText
		LPARAMETERS toJob
		DECLARE Sleep IN kernel32 AS FdHsSleep INTEGER
		IF !This.PollText(toJob) AND toJob.nTimeout > HS_TEXT_BASE
			This.oHost.NotifyKey("history.makingText", JUSTFNAME(toJob.cBinary), toJob.nTimeout)
		ENDIF
		DO WHILE !This.PollText(toJob)
			FdHsSleep(50)
		ENDDO
	ENDPROC

	*-- El texto de una versión nueva, en marcha: TextStep lo anota.
	PROCEDURE QueueText
		LPARAMETERS tcDir, tcName
		LOCAL loJob
		loJob = This.StartText(tcDir + tcName)
		IF This.oTextJobs.GetKey(UPPER(tcDir)) = 0
			This.oTextJobs.Add(loJob, UPPER(tcDir))
		ENDIF
	ENDPROC

	*-- En cada tick: los textos que acabaron se anotan en su version.txt (o su
	*-- versión se borra, si se descartó mientras tanto).
	PROCEDURE TextStep
		LOCAL lnI, loJob
		FOR lnI = This.oTextJobs.Count TO 1 STEP -1
			loJob = This.oTextJobs.Item(lnI)
			IF This.PollText(loJob)
				This.oTextJobs.Remove(lnI)
				This.TextDone(loJob)
			ENDIF
		ENDFOR
	ENDPROC

	PROTECTED PROCEDURE TextDone
		LPARAMETERS toJob
		IF toJob.lDiscard
			This.RemoveDir(toJob.cDir)
			RETURN
		ENDIF
		IF This.SetInfo(toJob.cDir, "text", toJob.cResult)
			This.oHost.Log("history: text of " + toJob.cBinary + ": " + toJob.cResult)
		ENDIF
	ENDPROC

	*-- Espera a todos los textos en marcha, hasta tnSeconds. .T. si acabaron.
	PROCEDURE WaitTexts
		LPARAMETERS tnSeconds
		LOCAL lnT0
		DECLARE Sleep IN kernel32 AS FdHsSleep INTEGER
		lnT0 = SECONDS()
		This.TextStep()
		DO WHILE This.oTextJobs.Count > 0 AND ABS(SECONDS() - lnT0) < tnSeconds
			FdHsSleep(50)
			This.TextStep()
		ENDDO
		RETURN This.oTextJobs.Count = 0
	ENDPROC

	*-- Cambia una clave de version.txt. .F. si la versión ya no está.
	PROCEDURE SetInfo
		LPARAMETERS tcDir, tcKey, tcValue
		LOCAL lcOld, lcSafety, loErr, llOk
		IF !FILE(tcDir + "version.txt")
			RETURN .F.
		ENDIF
		lcOld = This.InfoValue(tcDir, tcKey)
		*-- version.txt ya existe: con SET SAFETY ON, STRTOFILE preguntaría.
		lcSafety = SET("SAFETY")
		SET SAFETY OFF
		llOk = .F.
		TRY
			STRTOFILE(STRTRAN(FILETOSTR(tcDir + "version.txt"), CRLF + tcKey + "=" + lcOld + CRLF, CRLF + tcKey + "=" + tcValue + CRLF), ;
				tcDir + "version.txt")
			llOk = .T.
		CATCH TO loErr
			This.oHost.LogWarn("history: " + tcDir + "version.txt not updated: " + loErr.Message)
		FINALLY
			SET SAFETY &lcSafety
		ENDTRY
		RETURN llOk
	ENDPROC

	PROCEDURE EraseQuietly
		LPARAMETERS tcFile
		LOCAL loErr
		TRY
			*-- Dentro de un paquete MSIX, lo de la carpeta de datos se queda (MayErase).
			IF FILE(tcFile) AND (!PEMSTATUS(This.oHost, "MayErase", 5) OR This.oHost.MayErase(tcFile, "an old version in History"))
				ERASE (tcFile)
			ENDIF
		CATCH TO loErr
		ENDTRY
	ENDPROC

	*-- Los .out y .rc de vfp2text de otros días (un texto que no acabó a tiempo
	*-- los deja abiertos). Al cargar el plugin.
	PROCEDURE SweepTemp
		LOCAL lnN, lnI, lcDir
		LOCAL ARRAY laF[1]
		lcDir = ADDBS(SYS(2023))
		lnN = ADIR(laF, lcDir + "foxdock-history-*.*")
		FOR lnI = 1 TO lnN
			IF INLIST(LOWER(JUSTEXT(laF[lnI, 1])), "out", "rc") AND laF[lnI, 3] < DATE()
				This.EraseQuietly(lcDir + laF[lnI, 1])
			ENDIF
		ENDFOR
	ENDPROC

	*-- El texto de una versión que no lo tiene todavía: la de la línea base
	*-- (pendiente) o una cuyo texto sigue en marcha. Se espera ahora, si FoxKit
	*-- está, y se anota en su version.txt.
	PROCEDURE EnsureText
		LPARAMETERS tcFile, tcVersion
		LOCAL lcDir, lcState, loJob
		lcDir = This.FolderOf(tcFile) + tcVersion + "\"
		lcState = This.InfoValue(lcDir, "text")
		IF FILE(This.TextNameOf(lcDir + JUSTFNAME(tcFile))) AND !(lcState == HS_TEXT_MAKING)
			RETURN
		ENDIF
		IF !(lcState == HS_TEXT_PENDING OR lcState == HS_TEXT_MAKING) OR EMPTY(This.cVfp2Text)
			RETURN
		ENDIF
		IF This.oTextJobs.GetKey(UPPER(lcDir)) > 0
			loJob = This.oTextJobs.Item(UPPER(lcDir))
			This.WaitText(loJob)
			This.oTextJobs.Remove(UPPER(lcDir))
			This.TextDone(loJob)
			RETURN
		ENDIF
		*-- Pendiente, o en marcha en un VFP que ya se cerró: se hace ahora.
		loJob = This.StartText(lcDir + JUSTFNAME(tcFile))
		This.WaitText(loJob)
		IF This.SetInfo(lcDir, "text", loJob.cResult)
			This.oHost.Log("history: text of version " + tcVersion + " of " + tcFile + " made on demand: " + loJob.cResult)
		ENDIF
	ENDPROC

	*-- El texto de una versión ("" si no tiene). Si era de la línea base, lo
	*-- saca ahora (EnsureText).
	PROCEDURE VersionText
		LPARAMETERS tcFile, tcVersion
		LOCAL lcDir, lcText
		This.EnsureText(tcFile, tcVersion)
		lcDir = This.FolderOf(tcFile) + tcVersion + "\"
		lcText = This.TextNameOf(lcDir + JUSTFNAME(tcFile))
		RETURN IIF(FILE(lcText), FILETOSTR(lcText), "")
	ENDPROC

	*-- El texto del fichero tal como está ahora: una copia en temporal, y su
	*-- texto. "" si no se puede (sin FoxKit, o bloqueado por su diseñador).
	PROCEDURE CurrentText
		LPARAMETERS tcFile
		LOCAL lcTmp, lcSafety, lcTalk, lcText, loErr, llOk, lcMemo
		IF EMPTY(This.cVfp2Text) OR This.IsLocked(tcFile)
			RETURN ""
		ENDIF
		*-- En una variable: el nombre de COPY FILE (...) no admite una llamada
		*-- a un método (lo mismo que DO (FdApp()), error 31).
		lcMemo = This.MemoOf(tcFile)
		lcTmp = ADDBS(SYS(2023)) + "foxdock-history-" + SYS(2015) + "\"
		MKDIR (lcTmp)
		lcSafety = SET("SAFETY")
		lcTalk = SET("TALK")
		SET SAFETY OFF
		SET TALK OFF
		llOk = .F.
		TRY
			COPY FILE (tcFile) TO (lcTmp + JUSTFNAME(tcFile))
			COPY FILE (lcMemo) TO (lcTmp + JUSTFNAME(lcMemo))
			llOk = .T.
		CATCH TO loErr
		FINALLY
			SET TALK &lcTalk
			SET SAFETY &lcSafety
		ENDTRY
		lcText = ""
		IF llOk AND This.MakeText(lcTmp + JUSTFNAME(tcFile)) == JUSTFNAME(This.TextNameOf(lcTmp + JUSTFNAME(tcFile)))
			TRY
				lcText = FILETOSTR(This.TextNameOf(lcTmp + JUSTFNAME(tcFile)))
			CATCH TO loErr
				lcText = ""
			ENDTRY
		ENDIF
		This.RemoveDir(lcTmp)
		RETURN lcText
	ENDPROC

	*-- El diff de una versión contra el fichero de ahora (o contra la versión
	*-- más nueva, si el fichero está bloqueado). Devuelve el texto; vacío y
	*-- cMotivo en tcWhy si no se puede.
	PROCEDURE Diff
		LPARAMETERS tcFile, tcVersion, tcWhy
		LOCAL lcOld, lcNew, lcAgainst, lnN
		LOCAL ARRAY laV[1]
		tcWhy = ""
		IF !DIRECTORY(This.FolderOf(tcFile) + tcVersion, 1)
			tcWhy = "There is no version " + tcVersion + " of " + tcFile + "."
			RETURN ""
		ENDIF
		lcOld = This.VersionText(tcFile, tcVersion)
		IF EMPTY(lcOld)
			tcWhy = "Version " + tcVersion + " of " + tcFile + " has no text (" + ;
				This.InfoValue(This.FolderOf(tcFile) + tcVersion + "\", "text") + "), so there is nothing to compare."
			RETURN ""
		ENDIF
		lcNew = This.CurrentText(tcFile)
		lcAgainst = "the file now"
		IF EMPTY(lcNew)
			lnN = This.Versions(tcFile, @laV)
			lcNew = This.VersionText(tcFile, laV[lnN])
			lcAgainst = "version " + laV[lnN] + " (the newest; the file itself is " + ;
				IIF(This.IsLocked(tcFile), "locked by its designer", "not readable as text") + ")"
		ENDIF
		RETURN This.DiffText(lcOld, lcNew, "version " + tcVersion, lcAgainst)
	ENDPROC

	*-- Un diff de líneas: lo común de delante y de detrás se quita, y lo del
	*-- medio se alinea por la subsecuencia común más larga, si cabe (hasta
	*-- 250 000 celdas); si no, el medio sale entero como quitado y añadido.
	*-- Con 3 líneas de contexto alrededor de cada cambio.
	PROCEDURE DiffText
		LPARAMETERS tcOld, tcNew, tcOldName, tcNewName
		LOCAL lnA, lnB, lnP, lnS, lnN, lnM, lnI, lnJ, lnK, lcOut, lnAdd, lnDel, lnLast, lnCtx, lnOldNo, lnNewNo
		LOCAL ARRAY laA[1], laB[1], laOp[1], laTx[1], laL[1], laShow[1], laOld[1], laNew[1]
		lnA = ALINES(laA, tcOld)
		lnB = ALINES(laB, tcNew)
		lnP = 0
		DO WHILE lnP < lnA AND lnP < lnB AND laA[lnP + 1] == laB[lnP + 1]
			lnP = lnP + 1
		ENDDO
		lnS = 0
		DO WHILE lnS < lnA - lnP AND lnS < lnB - lnP AND laA[lnA - lnS] == laB[lnB - lnS]
			lnS = lnS + 1
		ENDDO
		lnN = lnA - lnP - lnS
		lnM = lnB - lnP - lnS
		lnK = 0
		FOR lnI = 1 TO lnP
			lnK = This.AddOp(@laOp, @laTx, lnK, "=", laA[lnI])
		ENDFOR
		IF lnN * lnM > 0 AND (lnN + 1) * (lnM + 1) <= 250000
			DIMENSION laL[lnN + 1, lnM + 1]
			laL = 0
			FOR lnI = lnN TO 1 STEP -1
				FOR lnJ = lnM TO 1 STEP -1
					IF laA[lnP + lnI] == laB[lnP + lnJ]
						laL[lnI, lnJ] = laL[lnI + 1, lnJ + 1] + 1
					ELSE
						laL[lnI, lnJ] = MAX(laL[lnI + 1, lnJ], laL[lnI, lnJ + 1])
					ENDIF
				ENDFOR
			ENDFOR
			lnI = 1
			lnJ = 1
			DO WHILE lnI <= lnN AND lnJ <= lnM
				DO CASE
					CASE laA[lnP + lnI] == laB[lnP + lnJ]
						lnK = This.AddOp(@laOp, @laTx, lnK, "=", laA[lnP + lnI])
						lnI = lnI + 1
						lnJ = lnJ + 1
					CASE laL[lnI + 1, lnJ] >= laL[lnI, lnJ + 1]
						lnK = This.AddOp(@laOp, @laTx, lnK, "-", laA[lnP + lnI])
						lnI = lnI + 1
					OTHERWISE
						lnK = This.AddOp(@laOp, @laTx, lnK, "+", laB[lnP + lnJ])
						lnJ = lnJ + 1
				ENDCASE
			ENDDO
			FOR lnI = lnI TO lnN
				lnK = This.AddOp(@laOp, @laTx, lnK, "-", laA[lnP + lnI])
			ENDFOR
			FOR lnJ = lnJ TO lnM
				lnK = This.AddOp(@laOp, @laTx, lnK, "+", laB[lnP + lnJ])
			ENDFOR
		ELSE
			FOR lnI = 1 TO lnN
				lnK = This.AddOp(@laOp, @laTx, lnK, "-", laA[lnP + lnI])
			ENDFOR
			FOR lnJ = 1 TO lnM
				lnK = This.AddOp(@laOp, @laTx, lnK, "+", laB[lnP + lnJ])
			ENDFOR
		ENDIF
		FOR lnI = lnA - lnS + 1 TO lnA
			lnK = This.AddOp(@laOp, @laTx, lnK, "=", laA[lnI])
		ENDFOR
		*-- Qué líneas se enseñan: los cambios y 3 de contexto a cada lado. Y el
		*-- número de línea de cada una, en el viejo y en el nuevo.
		lnCtx = 3
		DIMENSION laShow[MAX(lnK, 1)], laOld[MAX(lnK, 1)], laNew[MAX(lnK, 1)]
		laShow = .F.
		lnOldNo = 0
		lnNewNo = 0
		lnAdd = 0
		lnDel = 0
		FOR lnI = 1 TO lnK
			lnOldNo = lnOldNo + IIF(laOp[lnI] == "+", 0, 1)
			lnNewNo = lnNewNo + IIF(laOp[lnI] == "-", 0, 1)
			laOld[lnI] = lnOldNo
			laNew[lnI] = lnNewNo
			IF !(laOp[lnI] == "=")
				lnAdd = lnAdd + IIF(laOp[lnI] == "+", 1, 0)
				lnDel = lnDel + IIF(laOp[lnI] == "-", 1, 0)
				FOR lnJ = MAX(1, lnI - lnCtx) TO MIN(lnK, lnI + lnCtx)
					laShow[lnJ] = .T.
				ENDFOR
			ENDIF
		ENDFOR
		lcOut = "--- " + tcOldName + CRLF + "+++ " + tcNewName + CRLF + ;
			TRANSFORM(lnDel) + " line(s) removed, " + TRANSFORM(lnAdd) + " added" + CRLF
		IF lnAdd + lnDel = 0
			RETURN lcOut + "(no differences)" + CRLF
		ENDIF
		lnLast = -1
		FOR lnI = 1 TO lnK
			IF !laShow[lnI]
				LOOP
			ENDIF
			IF lnLast # lnI - 1
				lcOut = lcOut + "@@ line " + TRANSFORM(laOld[lnI]) + " of the old, " + TRANSFORM(laNew[lnI]) + " of the new @@" + CRLF
			ENDIF
			lcOut = lcOut + ICASE(laOp[lnI] == "-", "- ", laOp[lnI] == "+", "+ ", "  ") + laTx[lnI] + CRLF
			lnLast = lnI
		ENDFOR
		RETURN lcOut
	ENDPROC

	PROTECTED PROCEDURE AddOp
		LPARAMETERS taOp, taTx, tnK, tcOp, tcText
		tnK = tnK + 1
		DIMENSION taOp[tnK], taTx[tnK]
		taOp[tnK] = tcOp
		taTx[tnK] = tcText
		RETURN tnK
	ENDPROC

	*==============================================================
	* Restaurar.
	*==============================================================

	*-- Devuelve "" si restauró (y deja en cLastNote la versión que tomó
	*-- antes), o el motivo por el que no.
	PROCEDURE Restore
		LPARAMETERS tcFile, tcVersion
		LOCAL lcDir, lcMemo, lcTitle, lcBefore, lcSafety, lcTalk, loErr, lcFail
		lcDir = This.FolderOf(tcFile) + tcVersion + "\"
		lcMemo = This.MemoOf(tcFile)
		IF EMPTY(tcVersion) OR !FILE(lcDir + "version.txt")
			RETURN "There is no version " + tcVersion + " of " + tcFile + "."
		ENDIF
		IF !FILE(lcDir + JUSTFNAME(tcFile)) OR !FILE(lcDir + JUSTFNAME(lcMemo))
			RETURN "Version " + tcVersion + " of " + tcFile + " does not have both the binary and its memo; nothing restored."
		ENDIF
		lcTitle = This.DesignerOf(tcFile)
		IF !EMPTY(lcTitle)
			RETURN JUSTFNAME(tcFile) + " is open in " + lcTitle + ": close it first. Nothing restored."
		ENDIF
		IF This.IsLocked(tcFile)
			RETURN tcFile + " is in use (something has it open): nothing restored."
		ENDIF
		lcBefore = This.TakeVersion(tcFile, "before restoring " + tcVersion)
		IF EMPTY(lcBefore)
			RETURN "The current state of " + tcFile + " could not be kept first (" + This.cLastNote + "), so nothing was restored."
		ENDIF
		lcSafety = SET("SAFETY")
		lcTalk = SET("TALK")
		SET SAFETY OFF
		SET TALK OFF
		lcFail = ""
		TRY
			COPY FILE (lcDir + JUSTFNAME(tcFile)) TO (tcFile)
			COPY FILE (lcDir + JUSTFNAME(lcMemo)) TO (lcMemo)
		CATCH TO loErr
			lcFail = TRANSFORM(loErr.ErrorNo) + " " + loErr.Message
		FINALLY
			SET TALK &lcTalk
			SET SAFETY &lcSafety
		ENDTRY
		IF !EMPTY(lcFail)
			This.oHost.LogFault("history: restoring " + tcFile + " to " + tcVersion + " failed: " + lcFail)
			RETURN "Restoring failed (" + lcFail + "). The state before is version " + lcBefore + "."
		ENDIF
		This.cLastNote = lcBefore
		This.oHost.NotifyKey("history.restored", JUSTFNAME(tcFile), tcVersion, lcBefore)
		RETURN ""
	ENDPROC

	*==============================================================
	* Los diseñadores, por sus ventanas.
	*==============================================================

	*-- «Form Designer - x.scx» -> x.scx; «Class Designer - l.vcx (cls)» ->
	*-- l.vcx. Lo demás, "" (la barra «Form Designer», sin fichero, también).
	PROCEDURE DesignedName
		LPARAMETERS tcTitle
		LOCAL lnI, lcKind, lcName
		LOCAL ARRAY laK[1]
		FOR lnI = 1 TO ALINES(laK, HS_KINDS, 1, ",")
			lcKind = laK[lnI] + " Designer - "
			IF LEFT(tcTitle, LEN(lcKind)) == lcKind
				lcName = ALLTRIM(SUBSTR(tcTitle, LEN(lcKind) + 1))
				IF laK[lnI] == "Class" AND " (" $ lcName
					lcName = LEFT(lcName, RAT(" (", lcName) - 1)
				ENDIF
				RETURN lcName
			ENDIF
		ENDFOR
		RETURN ""
	ENDPROC

	*-- La ventana del diseñador que tiene ese fichero, o "".
	PROCEDURE DesignerOf
		LPARAMETERS tcFile
		LOCAL loJ, loList, lnI, loW, lcTitle
		loJ = This.oHost.oJson
		loList = loJ.Split(This.oHost.Windows.List())
		FOR lnI = 1 TO loList.Count
			loW = loJ.ToObject(loList.Item(lnI))
			lcTitle = IIF(PEMSTATUS(loW, "title", 5), loW.title, "")
			IF !EMPTY(lcTitle) AND LOWER(This.DesignedName(lcTitle)) == LOWER(JUSTFNAME(tcFile))
				RETURN lcTitle
			ENDIF
		ENDFOR
		RETURN ""
	ENDPROC

	*-- De un nombre a su ruta: el objeto del diseñador si es el de delante
	*-- (SYS(1271), formularios y clases); si no, los Files de los proyectos
	*-- abiertos; si no, FULLPATH con el SET PATH. "" si no se encuentra.
	PROCEDURE Resolve
		LPARAMETERS tcName, tcTitle
		LOCAL lcPath, loP, loF, loErr, lnN
		LOCAL ARRAY laSel[1]
		lcPath = ""
		IF !EMPTY(tcTitle) AND UPPER(WONTOP()) == UPPER(tcTitle)
			TRY
				lnN = ASELOBJ(laSel, 1)
				IF lnN > 0
					lcPath = TRANSFORM(SYS(1271, laSel[1]))
				ENDIF
			CATCH TO loErr
				lcPath = ""
			ENDTRY
			IF !(LOWER(JUSTFNAME(lcPath)) == LOWER(tcName)) OR !FILE(lcPath)
				lcPath = ""
			ENDIF
		ENDIF
		IF EMPTY(lcPath)
			TRY
				FOR EACH loP IN _VFP.Projects
					FOR EACH loF IN loP.Files
						IF LOWER(JUSTFNAME(loF.Name)) == LOWER(tcName)
							lcPath = loF.Name
							EXIT
						ENDIF
					ENDFOR
					IF !EMPTY(lcPath)
						EXIT
					ENDIF
				ENDFOR
			CATCH TO loErr
				lcPath = ""
			ENDTRY
		ENDIF
		IF EMPTY(lcPath) AND FILE(FULLPATH(tcName))
			lcPath = FULLPATH(tcName)
		ENDIF
		RETURN lcPath
	ENDPROC

	*-- El fichero que pide el agente: una ruta que existe; o un nombre, entre
	*-- los que tienen historial (si hay varios con ese nombre, lo dice); o un
	*-- nombre que se encuentra como en Resolve. tcWhy lleva el motivo si no.
	PROCEDURE FindFile
		LPARAMETERS tcArg, tcWhy
		LOCAL loAll, lnI, lcHit, lnHits, lcList
		tcWhy = ""
		tcArg = ALLTRIM(tcArg)
		IF EMPTY(tcArg)
			tcWhy = "'file' is required: the binary (its path, or its name if only one file with history has it)."
			RETURN ""
		ENDIF
		IF ("\" $ tcArg OR ":" $ tcArg) AND FILE(tcArg)
			RETURN FULLPATH(tcArg)
		ENDIF
		loAll = This.Files()
		lcHit = ""
		lnHits = 0
		lcList = ""
		FOR lnI = 1 TO loAll.Count
			IF LOWER(JUSTFNAME(loAll.Item(lnI))) == LOWER(JUSTFNAME(tcArg))
				lnHits = lnHits + 1
				lcHit = loAll.Item(lnI)
				lcList = lcList + IIF(EMPTY(lcList), "", ", ") + lcHit
			ENDIF
		ENDFOR
		DO CASE
			CASE lnHits = 1
				RETURN lcHit
			CASE lnHits > 1
				tcWhy = "Several files with history are called " + JUSTFNAME(tcArg) + ": " + lcList + ". Give the full path."
				RETURN ""
		ENDCASE
		lcHit = This.Resolve(JUSTFNAME(tcArg), "")
		IF EMPTY(lcHit)
			tcWhy = "No file " + tcArg + " was found (not among the files with history, nor in an open project, nor in SET PATH)."
		ENDIF
		RETURN lcHit
	ENDPROC

	*==============================================================
	* El menú y la lista.
	*==============================================================

	*-- El fichero del diseñador de delante, o "".
	PROCEDURE CurrentFile
		LOCAL lcName, lcTitle
		lcTitle = This.TitleOfTop()
		lcName = This.DesignedName(lcTitle)
		IF EMPTY(lcName)
			RETURN ""
		ENDIF
		RETURN This.Resolve(lcName, lcTitle)
	ENDPROC

	*-- WONTOP() viene en mayúsculas; el título como se escribió sale de la lista.
	PROCEDURE TitleOfTop
		LOCAL loJ, loList, lnI, loW, lcTop
		lcTop = UPPER(WONTOP())
		loJ = This.oHost.oJson
		loList = loJ.Split(This.oHost.Windows.List())
		FOR lnI = 1 TO loList.Count
			loW = loJ.ToObject(loList.Item(lnI))
			IF PEMSTATUS(loW, "title", 5) AND UPPER(loW.title) == lcTop
				RETURN loW.title
			ENDIF
		ENDFOR
		RETURN ""
	ENDPROC

	PROCEDURE ShowHistory
		LOCAL lcFile
		lcFile = This.CurrentFile()
		IF VARTYPE(This.oForm) == "O" AND !ISNULL(This.oForm)
			This.oForm.Fill(lcFile)
			This.oForm.Show()
			RETURN
		ENDIF
		This.oForm = CREATEOBJECT("HistoryForm", This)
		This.oForm.Fill(lcFile)
		This.oForm.Show()
	ENDPROC

	PROCEDURE OpenFolder
		LOCAL lcDir
		lcDir = This.cRoot
		IF !DIRECTORY(lcDir, 1)
			This.MakeDirs(lcDir)
		ENDIF
		RUN /N explorer.exe "&lcDir"
	ENDPROC

	*-- El diff en un editor, de solo lectura.
	PROCEDURE ShowDiff
		LPARAMETERS tcFile, tcVersion
		LOCAL lcText, lcWhy, lcOut, lcSafety
		lcWhy = ""
		lcText = This.Diff(tcFile, tcVersion, @lcWhy)
		IF EMPTY(lcText)
			This.oHost.NotifyQuoted("history.said", lcWhy)
			RETURN .F.
		ENDIF
		lcOut = ADDBS(SYS(2023)) + "foxdock-history-" + JUSTSTEM(tcFile) + "-" + tcVersion + ".diff.txt"
		*-- El segundo Diff de la misma versión lo sobrescribe: sin preguntar.
		lcSafety = SET("SAFETY")
		SET SAFETY OFF
		STRTOFILE(lcText, lcOut)
		SET SAFETY &lcSafety
		MODIFY FILE (lcOut) NOWAIT NOEDIT
		RETURN .T.
	ENDPROC

	*==============================================================
	* Carpetas.
	*==============================================================

	*-- MKDIR nivel a nivel (vfpdocs no dice que cree los de en medio).
	PROCEDURE MakeDirs
		LPARAMETERS tcDir
		LOCAL lcPath, lnI, lnN
		LOCAL ARRAY laP[1]
		lnN = ALINES(laP, CHRTRAN(ADDBS(tcDir), "/", "\"), 1, "\")
		lcPath = ""
		FOR lnI = 1 TO lnN
			IF EMPTY(laP[lnI])
				LOOP
			ENDIF
			lcPath = lcPath + laP[lnI] + "\"
			IF lnI > 1 AND !DIRECTORY(lcPath, 1)
				MKDIR (lcPath)
			ENDIF
		ENDFOR
	ENDPROC

	*-- Borra una carpeta de versión (o la temporal): sus ficheros y ella.
	PROCEDURE RemoveDir
		LPARAMETERS tcDir
		LOCAL lnN, lnI, loErr
		LOCAL ARRAY laF[1]
		IF !DIRECTORY(tcDir, 1)
			RETURN
		ENDIF
		*-- Dentro de un paquete MSIX, la carpeta de datos no se poda (MayErase).
		IF PEMSTATUS(This.oHost, "MayErase", 5) AND !This.oHost.MayErase(ADDBS(tcDir), "a version folder of History")
			RETURN
		ENDIF
		TRY
			lnN = ADIR(laF, ADDBS(tcDir) + "*.*", "H")
			FOR lnI = 1 TO lnN
				ERASE (ADDBS(tcDir) + laF[lnI, 1])
			ENDFOR
			RMDIR (tcDir)
		CATCH TO loErr
			This.oHost.LogWarn("history: could not remove " + tcDir + ": " + loErr.Message)
		ENDTRY
	ENDPROC
ENDDEFINE


*==================================================================
* La lista de versiones: un formulario modeless, sin MESSAGEBOX. Diff abre el
* diff en un editor; Restore lo restaura (si ningún diseñador tiene el
* fichero); lo que pasa lo dicen el log y la barra de estado.
*==================================================================
*-- Se estira (borde redimensionable y maximizar) con la lista
*-- de versiones; los botones, pegados abajo.
DEFINE CLASS HistoryForm AS Form
	Caption = "FoxDock - History"
	Width = 620
	Height = 340
	AutoCenter = .T.
	BorderStyle = 3
	MaxButton = .T.
	MinWidth = 620
	MinHeight = 340
	ShowWindow = 0
	WindowType = 0
	oPlugin = .NULL.
	cFile = ""

	ADD OBJECT lblFile AS Label WITH Caption = "File", Left = 10, Top = 13, AutoSize = .T.
	ADD OBJECT cboFile AS ComboBox WITH Left = 45, Top = 9, Width = 565, Style = 2, Anchor = 11
	ADD OBJECT lstVersions AS ListBox WITH Left = 10, Top = 40, Width = 600, Height = 250, ;
		ColumnCount = 4, ColumnWidths = "120,130,200,140", Anchor = 15
	ADD OBJECT cmdDiff AS CommandButton WITH Caption = "\<Diff", Left = 10, Top = 300, Width = 90, Height = 28, Anchor = 6
	ADD OBJECT cmdRestore AS CommandButton WITH Caption = "\<Restore", Left = 110, Top = 300, Width = 90, Height = 28, Anchor = 6
	ADD OBJECT cmdFolder AS CommandButton WITH Caption = "Open \<folder", Left = 210, Top = 300, Width = 110, Height = 28, ;
		Anchor = 6
	*-- ESC cierra la ventana, como Close (Cancel = .T., como las de Data).
	ADD OBJECT cmdClose AS CommandButton WITH Caption = "\<Close", Left = 520, Top = 300, Width = 90, Height = 28, ;
		Cancel = .T., Anchor = 12

	PROCEDURE Init
		LPARAMETERS toPlugin
		This.oPlugin = toPlugin
		This.Texts()
	ENDPROC

	*-- Los textos, en el idioma de FoxDock, también al cambiarlo con la
	*-- ventana abierta (el fichero elegido se queda).
	PROCEDURE Texts
		LOCAL loH, lnW, lnRight
		loH = This.oPlugin.oHost
		This.Caption = loH.Translate("history.form.caption")
		This.lblFile.Caption = loH.Translate("history.form.file")
		*-- El combo, detrás de su etiqueta, para que no la tape un texto largo.
		*-- La etiqueta se mide con TXTWIDTH (en el Init, el Width de una AutoSize
		*-- no es el de su texto nuevo). El combo acaba donde acababa. El Anchor,
		*-- a 0 y de vuelta: el anclaje va por la posición de cuando se puso
		*-- (vfpdocs, Anchor).
		lnW = CEILING(TXTWIDTH(This.lblFile.Caption, This.lblFile.FontName, This.lblFile.FontSize, IIF(This.lblFile.FontBold, "B", "N")) * ;
			FONTMETRIC(6, This.lblFile.FontName, This.lblFile.FontSize, IIF(This.lblFile.FontBold, "B", "N")))
		IF This.lblFile.Left + lnW + 8 > This.cboFile.Left
			lnRight = This.cboFile.Left + This.cboFile.Width
			This.cboFile.Anchor = 0
			This.cboFile.Left = This.lblFile.Left + lnW + 8
			This.cboFile.Width = lnRight - This.cboFile.Left
			This.cboFile.Anchor = 11
		ENDIF
		This.cmdDiff.Caption = loH.Translate("history.form.diff")
		This.cmdRestore.Caption = loH.Translate("history.form.restore")
		This.cmdFolder.Caption = loH.Translate("history.form.folder")
		This.cmdClose.Caption = loH.Translate("history.form.close")
		*-- Los tres botones de la izquierda, tan anchos como su texto
		*-- («Wiederherstellen» no cabe en 90 px) y nunca más estrechos que en
		*-- diseño, uno detrás de otro; Close sigue en su esquina.
		This.FitButton(This.cmdDiff, 90, This.cmdDiff.Left)
		This.FitButton(This.cmdRestore, 90, This.cmdDiff.Left + This.cmdDiff.Width + 10)
		This.FitButton(This.cmdFolder, 110, This.cmdRestore.Left + This.cmdRestore.Width + 10)
	ENDPROC

	*-- Un botón a tnLeft, con el ancho de su texto más 16 px de aire y bordes, y
	*-- tnMin como poco. El Anchor, a 0 y de vuelta, como el del combo.
	PROCEDURE FitButton
		LPARAMETERS toB, tnMin, tnLeft
		LOCAL lnW, lnAnchor
		lnW = CEILING(TXTWIDTH(STRTRAN(toB.Caption, "\<", ""), toB.FontName, toB.FontSize, IIF(toB.FontBold, "B", "N")) * ;
			FONTMETRIC(6, toB.FontName, toB.FontSize, IIF(toB.FontBold, "B", "N")))
		lnAnchor = toB.Anchor
		toB.Anchor = 0
		toB.Left = tnLeft
		toB.Width = MAX(tnMin, lnW + 16)
		toB.Anchor = lnAnchor
	ENDPROC

	*-- Los ficheros con historial, con tcFile elegido (o el primero).
	PROCEDURE Fill
		LPARAMETERS tcFile
		LOCAL loAll, lnI, lnSel
		loAll = This.oPlugin.Files()
		This.cboFile.Clear()
		lnSel = 0
		FOR lnI = 1 TO loAll.Count
			This.cboFile.AddItem(loAll.Item(lnI))
			IF !EMPTY(tcFile) AND UPPER(loAll.Item(lnI)) == UPPER(tcFile)
				lnSel = lnI
			ENDIF
		ENDFOR
		IF !EMPTY(tcFile) AND lnSel = 0
			This.cboFile.AddItem(tcFile)
			lnSel = This.cboFile.ListCount
		ENDIF
		IF This.cboFile.ListCount > 0
			This.cboFile.ListIndex = MAX(lnSel, 1)
		ENDIF
		This.LoadVersions()
	ENDPROC

	*-- Las versiones del fichero elegido, la más nueva arriba.
	PROCEDURE LoadVersions
		LOCAL lnN, lnI, lcDir, lnRow
		LOCAL ARRAY laV[1]
		This.lstVersions.Clear()
		This.cFile = IIF(This.cboFile.ListIndex > 0, This.cboFile.List(This.cboFile.ListIndex), "")
		IF EMPTY(This.cFile)
			RETURN
		ENDIF
		lnN = This.oPlugin.Versions(This.cFile, @laV)
		FOR lnI = lnN TO 1 STEP -1
			lcDir = This.oPlugin.FolderOf(This.cFile) + laV[lnI] + "\"
			This.lstVersions.AddItem(laV[lnI])
			lnRow = This.lstVersions.ListCount
			This.lstVersions.List(lnRow, 2) = This.oPlugin.InfoValue(lcDir, "taken")
			This.lstVersions.List(lnRow, 3) = This.oPlugin.InfoValue(lcDir, "reason")
			This.lstVersions.List(lnRow, 4) = "text: " + This.oPlugin.InfoValue(lcDir, "text")
		ENDFOR
		IF This.lstVersions.ListCount > 0
			This.lstVersions.ListIndex = 1
		ENDIF
	ENDPROC

	PROCEDURE SelectedVersion
		RETURN IIF(This.lstVersions.ListIndex > 0, This.lstVersions.List(This.lstVersions.ListIndex, 1), "")
	ENDPROC

	PROCEDURE cboFile.InteractiveChange
		Thisform.LoadVersions()
	ENDPROC

	*-- Los botones son una entrada más (como el Timer y las barras): con el SET
	*-- TALK ON del IDE, cada asignación del plugin saldría en la barra de estado.
	PROCEDURE cmdDiff.Click
		LOCAL lcV, lcTalk
		lcTalk = SET("TALK")
		SET TALK OFF
		lcV = Thisform.SelectedVersion()
		IF !EMPTY(lcV)
			Thisform.oPlugin.ShowDiff(Thisform.cFile, lcV)
		ENDIF
		SET TALK &lcTalk
	ENDPROC

	PROCEDURE cmdRestore.Click
		LOCAL lcV, lcWhy, lcTalk
		lcTalk = SET("TALK")
		SET TALK OFF
		lcV = Thisform.SelectedVersion()
		IF !EMPTY(lcV)
			lcWhy = Thisform.oPlugin.Restore(Thisform.cFile, lcV)
			IF !EMPTY(lcWhy)
				Thisform.oPlugin.oHost.NotifyQuoted("history.said", lcWhy)
			ENDIF
			Thisform.LoadVersions()
		ENDIF
		SET TALK &lcTalk
	ENDPROC

	PROCEDURE cmdFolder.Click
		Thisform.oPlugin.OpenFolder()
	ENDPROC

	PROCEDURE cmdClose.Click
		Thisform.Release()
	ENDPROC

	PROCEDURE Destroy
		IF VARTYPE(This.oPlugin) == "O"
			This.oPlugin.oForm = .NULL.
		ENDIF
		This.oPlugin = .NULL.
	ENDPROC
ENDDEFINE
