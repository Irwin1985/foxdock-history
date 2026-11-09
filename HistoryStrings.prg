*==================================================================
* HistoryStrings.prg: las cadenas del plugin history, en inglés,
* español y alemán. Lo ejecuta el host al cargar el plugin (LoadPluginStrings),
* antes de su BuildMenu: una llamada toHost.AddString(<idioma>, <clave>, <texto>)
* por cadena. Las tres listas llevan las mismas claves, en el mismo orden; una que
* falte en español o alemán sale en inglés. {1} a {4}, los valores. \< marca la
* tecla de acceso. Los nombres propios (FoxDock, FoxAgent, VFP, GUID, JSON) no se
* traducen. Fichero en CP1252, con los acentos escritos: lo lee el usuario.
*==================================================================

LPARAMETERS toHost

*-- English
toHost.AddString("en", "history.title", "History")
toHost.AddString("en", "history.bar.show", "History of the current \<file...")
toHost.AddString("en", "history.bar.show.message", "The saved versions of the file in the designer in front")
toHost.AddString("en", "history.bar.folder", "Open history \<folder")
toHost.AddString("en", "history.bar.folder.message", "Where FoxDock keeps the versions")
toHost.AddString("en", "history.makingText", "History: making the text of {1}; it can take up to {2} s")
toHost.AddString("en", "history.restored", "History: {1} restored to version {2} (the state before is version {3})")
toHost.AddString("en", "history.said", "History: {1}")
toHost.AddString("en", "history.form.caption", "FoxDock - History")
toHost.AddString("en", "history.form.file", "File")
toHost.AddString("en", "history.form.diff", "\<Diff")
toHost.AddString("en", "history.form.restore", "\<Restore")
toHost.AddString("en", "history.form.folder", "Open \<folder")
toHost.AddString("en", "history.form.close", "\<Close")

*-- Español
toHost.AddString("es", "history.title", "Historial")
toHost.AddString("es", "history.bar.show", "Historial del \<fichero actual...")
toHost.AddString("es", "history.bar.show.message", "Las versiones guardadas del fichero del diseñador que está delante")
toHost.AddString("es", "history.bar.folder", "Abrir la \<carpeta del historial")
toHost.AddString("es", "history.bar.folder.message", "Donde FoxDock guarda las versiones")
toHost.AddString("es", "history.makingText", "Historial: haciendo el texto de {1}; puede tardar hasta {2} s")
toHost.AddString("es", "history.restored", "Historial: {1} restaurado a la versión {2} (el estado anterior es la versión {3})")
toHost.AddString("es", "history.said", "Historial: {1}")
toHost.AddString("es", "history.form.caption", "FoxDock - Historial")
toHost.AddString("es", "history.form.file", "Fichero")
toHost.AddString("es", "history.form.diff", "\<Diferencias")
toHost.AddString("es", "history.form.restore", "\<Restaurar")
toHost.AddString("es", "history.form.folder", "Abrir \<carpeta")
toHost.AddString("es", "history.form.close", "C\<errar")

*-- Deutsch
toHost.AddString("de", "history.title", "Verlauf")
toHost.AddString("de", "history.bar.show", "Verlauf der aktuellen \<Datei...")
toHost.AddString("de", "history.bar.show.message", "Die gespeicherten Versionen der Datei im vorderen Designer")
toHost.AddString("de", "history.bar.folder", "Verlaufs\<ordner öffnen")
toHost.AddString("de", "history.bar.folder.message", "Wo FoxDock die Versionen aufbewahrt")
toHost.AddString("de", "history.makingText", "Verlauf: Der Text von {1} wird erstellt; das kann bis zu {2} s dauern")
toHost.AddString("de", "history.restored", "Verlauf: {1} auf Version {2} zurückgesetzt (der vorherige Stand ist Version {3})")
toHost.AddString("de", "history.said", "Verlauf: {1}")
toHost.AddString("de", "history.form.caption", "FoxDock - Verlauf")
toHost.AddString("de", "history.form.file", "Datei")
toHost.AddString("de", "history.form.diff", "\<Unterschiede")
toHost.AddString("de", "history.form.restore", "\<Wiederherstellen")
toHost.AddString("de", "history.form.folder", "\<Ordner öffnen")
toHost.AddString("de", "history.form.close", "\<Schließen")
