[![macOS 10.13+](https://img.shields.io/badge/macOS-10.13+-888)](#install)
[![Current release](https://img.shields.io/github/release/relikd/Menuscript)](https://github.com/relikd/Menuscript/releases)
[![All downloads](https://img.shields.io/github/downloads/relikd/Menuscript/total)](https://github.com/relikd/Menuscript/releases)

<img src="img/icon.svg" width="180" height="180">

# Menuscript

A menu bar script executor.

<img src="img/screenshot.png" width="390" height="205">

Menuscript adds a status bar menu to call custom (user defined) scripts.
The app reads the content of a directory and adds all executable files to the status menu.
See [res/examples](res/examples/) directory.


## Usage

1) Define your own script directory in Preferences.
2) Add subdirectories and scripts to your scripts dir.
3) Run a script from your status menu.
4) Depending on your script action, you may want to allow `Full Disk Access` for Menuscript.

*Note:* Menuscript reloads the directory structure each time you open the status menu, no need to restart the app.


### Requirements

Script files are called as is.
Therefore each script __must__ have the executable flag (`chmod 755` or `chmod +x`) and __must__ execute itself on double-click.
The latter can be achieved by adding a shebang (e.g., `#!/bin/sh`) to the script file.
You may want to omit the file extension (in case of Python, that would launch the editor instead of executing the script).

Apart from that, there is no limitation on the script language.
You can use Bash, Python, Swift, Ruby, whatever.
And of course, you can always write a script wrapper to call something else.

=> If you can run the script with `open` (e.g., `open myscript`), it will work in the status menu too.


### Configuration

There are a few ways to modify the menu structure:

#### Menu Icon

A subdirectory can have a custom icon if the folder contains an image file named `icon.X` (where `X` is one of: `svg`, `png`, `jpg`, `jpeg`, `gif`, `ico`, `icns`).
For menu items, the icon file should be named exactly like the script file plus one of the icon extensions (e.g., `cmd.sh` -> `cmd.sh.png`).

#### Sort Order

By default, menu items are sorted in alphabetic order (case-insensitive).
You can change the item order by prepending numbers to the filename.
It does not matter whether you prepend your files with `42` or `42.` or `42 - `, as long as the first character is a number.

You dont need to rename all items either.
Each item has a default numerical order of `100`.
By prepending a number lower or higher than 100, you can place items at the top or bottom of the menu respectively.

#### Modifier Flags

Modifier flags change what happens if you click on the menu item.
Flags are defined by adding a text snippet to the filename.
These constant strings are defined:

- __[txt]__: Execute the script and dump all output in a new `TextEdit` window (useful for reports or log files, etc.)
- __[verbose]__: Usually, script files are executed in the background.
  With this flag, a new `Terminal` window will open and show the activley running script (useful for continuous output like `top` or `netstat -w`, etc.)
- __[inactive]__: Make menu item non-clickable (will appear greyed out)
- __[ignore]__: Do not show menu item (no menu entry)
- __[dyn]__: If set, the script file is responsible to generate its menu items.
  See [Dynamic Menus](#dynamic-menus).

#### Dynamic Menus

A single script file can generate a whole menu with multiple menu items ("[dyn]" flag).
As with other scripts, the filename will be used as menu title, in this case a menu folder.

The dynamic script is called with environment variables `ACTION` and `ITEM`.
Action can be one of: `list` (generate menu), `click` (item clicked), or `icon` (should return image data).

- `ACTION=list` is called without `ITEM` env and should return a list of menu items to display.
  Just print each menu item on a separate line.
  Item titles can use the same [modifier flags](#modifier-flags) as normal script files.
  But contrary to normal script files, sort order is defined by the dynamic script (you should not use numbers).
- `ACTION=click` always provides an `ITEM` with the currently clicked menu item title (after removing modifier flags).
  Your script should perform the intended action of the menu item.
- `ACTION=icon` may return an icon for any menu item (or return nothing to omit the icon).
  `ITEM` is empty for the folder menu icon and set to the menu title if called for an individual item (same as `click` action).
  You should return image data, e.g., by printing the content of an image file or returning SVG code.

You could use the icon to display an online status for example.
Keep in mind, that the menu is generated only once after the status menu opens.

Limitations: dynamic menus cannot have dynamic submenus.
Also, dynamic items cannot use the verbose flag (for now).
