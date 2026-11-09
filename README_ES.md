# foxdock-history

El plugin `history` de FoxDock, el sistema de plugins para el IDE de Visual FoxPro 9. Guarda la versión anterior de cada formulario, biblioteca de clases, informe, etiqueta y menú que editas, con diff y restaurar.

> También en inglés ([README.md](README.md)) y en alemán ([README_DE.md](README_DE.md)).

## Instalar

Hacen falta FoxDock y [FoxPack](https://irwinrodriguez.dev/products/foxpack).

- En FoxDock: **FoxDock > Plugins > Centro de plugins...**, **Disponibles**, elige `history` y pulsa **Instalar**.
- Desde una consola: `foxpack plugin add history`.

Si `history` vino con tu instalador de FoxDock, el centro de plugins enseña sus versiones nuevas en **Actualizaciones**.

## El plugin `history`

Cada vez que editas un formulario, una clase, un informe, una etiqueta o un menú, FoxDock guarda cómo
estaba antes. Si el cambio sale mal, lo devuelves a una versión anterior con un botón.

**Qué guarda.** Los binarios con memo: `.scx`, `.vcx`, `.frx`, `.lbx` y `.mnx`, **siempre con su
memo** (`.sct`, `.vct`, `.frt`, `.lbt`, `.mnt`). Nunca guarda uno sin el otro. Si FoxKit está instalado,
guarda también el texto de FoxBin2Prg (`.SC2`, `.VC2`...), que es lo que permite ver qué cambió. El
`.pjx` no, porque cambia a cada rato. El texto se hace por detrás, sin hacerte esperar: la versión está
desde el primer momento, y mientras tanto su texto dice `being made`. Un formulario grande puede tardar
un minuto; si pides el diff antes, **Diferencias** (Diff) lo espera.

**Dónde.** En `%LOCALAPPDATA%\FoxDock\history\`, una carpeta por cada carpeta de tus fuentes y, dentro,
una por fichero y otra por versión, con su fecha y hora:

```
history\c-proyectos-ventas-forms\clientes.scx\20261029-194004\
    clientes.scx   clientes.sct   clientes.SC2   version.txt
```

`version.txt` dice de qué fichero es, cuándo y por qué se tomó, y qué pasó con el texto.
**FoxDock > Historial > Abrir la carpeta del historial** (FoxDock > History > Open history folder) abre la carpeta.

**Cuándo.**

- **Si abres el fichero desde el Project Manager**, la versión se toma antes de que se abra el
  diseñador.
- **Al abrir un proyecto**, FoxDock copia los binarios del proyecto que todavía no tienen una versión
  igual (mismo tamaño, fecha y hora): unos pocos cada vez, sin que se note, y sin texto, que se saca
  cuando pides un diff. Es la **línea base**, y al acabar el log dice cuántos copió y cuántos ya estaban.
  Con un proyecto grande, la primera vez tarda unos minutos; las siguientes, solo comprueba, y tarda
  segundos. Un fichero que en ese momento está en uso (en un diseñador, o una librería de clases de un
  formulario abierto en el suyo) se salta, y se intenta otra vez la próxima vez que se abra el proyecto.
- **Si escribes `MODIFY FORM` en la ventana de comandos**, el diseñador abre el fichero y lo bloquea
  antes de que FoxDock se entere, y ya no se puede copiar. La versión de antes es entonces la guardada
  que sea igual al fichero (mismo tamaño, fecha y hora), también una vieja a la que lo devolviste con
  **Restaurar** (Restore); para un fichero de un proyecto abierto,
  ya la tiene la línea base. Si no la hay (un fichero suelto, fuera de un proyecto, que nunca pasó por
  FoxDock), el estado de antes se pierde, y el log lo dice.
- **Al cerrar el diseñador.** Si no cambiaste nada, la versión que se tomó al abrir se descarta: abrir y
  cerrar no llena el historial. Si cambiaste algo, se guarda también cómo ha quedado, así que la versión
  más nueva es siempre lo que hay en disco.

Se guardan 20 versiones por fichero; cuando se pasa, se borra la más vieja.

**Cómo se restaura.** **FoxDock > Historial > Historial del fichero actual...** (FoxDock > History > History of the current file...) enseña las versiones del
fichero del diseñador que tienes delante, o del que elijas de la lista.

- **Diferencias** abre en un editor las líneas que cambiaron entre esa versión y el fichero de ahora.
- **Restaurar** copia esa versión, binario y memo, sobre el fichero. Antes guarda el estado que va a
  pisar como una versión más, así que una restauración se deshace igual: restauras esa.

No pide confirmación: la confirmación es el botón. El aviso de arriba a la derecha de VFP y el log dicen lo que hizo.

**Lo que no hace.**

- **No restaura con el diseñador abierto.** Ciérralo antes; si no, lo dice y no toca nada.
- **Sin FoxKit no hay diff.** Las versiones se guardan igual (binario y memo), y `version.txt` dice
  `text: none (FoxKit not installed)`.
- **No sigue los ficheros que no encuentra.** Un `MODIFY FORM` de un fichero que no está en un proyecto
  abierto ni en el `SET PATH` no se puede encontrar por el título de la ventana, y el log lo dice.

**Las opciones** (`config.json`, `"options": { "history": { ... } }`): `extensions` (la lista de
extensiones, `"scx,vcx,frx,lbx,mnx"` por defecto), `maxVersions` (20), `baseline` (`true`: la línea
base al abrir un proyecto) y `settleSeconds` (3: cuando se cierra un diseñador y el fichero parece igual,
cuánto sigue mirando history antes de dar la edición por sin cambios, para lo guardado que llega tarde al disco).

Para el agente hay tres tools, `ide_history_list`, `ide_history_diff` e `ide_history_restore`:
AGENT-TOOLS_ES.md § 5.

## Sobre este manual

Este texto es la sección sobre `history` del manual de plugins de FoxDock. Las referencias a otras secciones (§) y a AGENT-TOOLS apuntan a los documentos que FoxDock instala en su carpeta `docs`.

## Licencia

MIT. Está en [LICENSE](LICENSE).
