# Todo list

## Top 1

- Handle queue: add multiples files queue (and set it with "queue")
- Add Menu (right click):
  - add/remove autolaunch support of a file
  - save file to display it on startup
  - locate file (already available on zoom icon)
- Display feature, to display the name of script instead of file

## 1 - Make user interface a "killer app"

- Process all files in 1 click (when autolaunch is false)
- Save default script selected in config file (last script selected for 1 trigger)
Example: 2 triggers for '.txt' files :
When I use script 1, it save it in
- start on startup => (cmd+alt+S save all files on main renderer as )
  - save a state non display but openable
- Add search on script Start selector when we have more than 5 scripts  
- Display "process all files" when there is files to process (better)
- Choose default script folder (handling Dropbox/Drive/Etc)
- Use better icon for non existing script (other than warning)
- Handle other thing than files (like text)


## 2 - Improve core scripting

- Integrate script-processor inside a headleass/worker windows
- Split files with ipc
- Add npm dependencies checker/adder in before (easy to do with npm lib)
- Multi-platform command (before/cmd/after)
- Prompt support
- choose what
- scan and add YAML 'inception' on a second YAML to accept cross parameters.
- chaining multiples cmd with array of commands
- support npm as dependencies packages (for plugins)
- Add a boilerplate support with core rules to fork into another app (for dev)
- hack css & js by a onStart feature

## 3 - Auto-updater

It's better.

## 4 - Support binary dependencies-packaging

Detect the kind of file you have added, and give you a way to process it. So, I need create a way to handle conversion cli tools (like [Calibre ebook-convert](ebook-convert), [ImageMagick](https://github.com/ImageMagick/ImageMagick)) into a multi-platform downloadable dependency on the need.

If you want to convert a kind of file, dependencies are downloaded if you need, and your file is processed.

To do. There is no already-functionnal-simple way to do.

My idea is make a library, a mix between homebrew, apt-get and npm, handling cross-platform apps, and installing it when needed.

## 5 - When I have time

-  edit default splashscreen gif (for Windows), [like this one](https://github.com/BoostIO/Boostnote/blob/master/resources/boostnote-install.gif):

![](https://raw.githubusercontent.com/BoostIO/Boostnote/master/resources/boostnote-install.gif)
