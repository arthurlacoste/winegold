<p align="center">
  <img src="src/assets/img/logo.svg" height="130">
  <h1 align="center">winegold</h1>
  <p align="center">A hackable drag and drop tool built with web technology<p>
  <p align="center"><a href="https://github.com/sindresorhus/xo"><img src="https://img.shields.io/badge/code_style-XO-5ed9c7.svg" alt="XO code style"></a></p>
</p>

Winegold is a swiss army knife for every drag and drop. It is built on [Electron](https://github.com/electron/electron).

3 steps to use winegold:
1. Download the favorite CLI app you love to use
2. [Create a simple trigger for it](docs/scripts.md)
3. And that's it! You can use every terminal/shell/CLI with a simple UI

This project adheres to the Contributor Covenant [code of conduct](code-of-conduct.md).
By participating, you are expected to uphold this code. Please report unacceptable behavior to arthak@gmail.com.

- [Read the script documentation](docs/scripts.md)

![demo of winegold app](src/assets/img/demo.gif)

Yes, I expected to be simple as this example.

One drag and drop, detecting what to do with this file. Or asking what you want to do with the files you've just dragged.

## What you can do with winegold

- Convert a file in multiple formats
- Process multiple files
- Use autolaunch feature to make a "one move drag and drop" easier than ever
- Convert your old shell script to a nice trigger who writes output in a file.
- Read content of a file and use it to do evil :see_no_evil:
- Use JavaScript or bash (equal everything!), what is your favorite flavor ?
- [Create your own scripts](docs/scripts.md) to use you drag and drop box


## Installing

### macOS

Download the latest [winegold release](https://github.com/arthurlacoste/winegold/releases).


### Windows

Download the latest [winegold installer](https://github.com/arthurlacoste/winegold/releases).  

`winegold-win-x32-setup-v0.0.1-alpha.exe` is for 32-bit & `winegold-win-x64-setup-v0.0.1-alpha.exe` 64-bit systems.


### GNU/·Linux

Download the latest [winegold release](https://github.com/arthurlacoste/winegold/releases) (x64 & x32).

The app haven't been tested on this platform! Every feedbacks are welcomed!

## What we want to do

**This is a wanted feature**

Detect the kind of file you added, and give you a way to process it. So, I need to create a way to handle conversion cli tools (like [Calibre ebook-convert](ebook-convert), [ImageMagick](https://github.com/ImageMagick/ImageMagick)) into a multi-platform downloadable dependency on the need.

If you want to convert a kind of file, dependencies are downloaded if you need, and your file is processed.

Other (& simpler) todo:

- [See the todo page](docs/todo.md).

## Everything is scripting

We want to put file into the center of everything.

For this example, here is the script you describing how everthing works :

```yaml

name: Convert to mobi

trigger :
  fileExtension:
   - pdf
   - epub

cmd:
  exec: ebook-convert {{file}} {{file}}.mobi --verbose

autolaunch: true

```

To understand, this script executes the shell command ebook-convert when a PDF or EPUB is found, and convert it to mobi. **You need to have ebook-convert** on your computer to use this script, but we work on another way to do this.

This script auto launch the command when file is dragged.

As you can see, we using YAML to provide a **human readable  kind of file**.

You can add your own script by dragging a script called `"myscript.add.yml"`. This action adds a trigger and a command for your own needs.

- [Read the script documentation](docs/scripts.md)
- [Know more about who YAML works](https://yaml.irz.fr)

## Contribute

### Requirement

Use Eslint/XO syntax (xo --fix is used when you make `yarn test`. Install here:

```
npm install xo -g
```

### Get the code

```
git clone https://github.com/arthurlacoste/winegold.git
cd winegold
npm install
```

### Run the app

```
npm start
```

### Watch the code

Restart the app automatically every time code changes. Useful during development.

```
npm run watch
```
### Build the app

Builds app binaries for Mac, Linux, and Windows.

```
npm run build [platform]
```

Where `[platform]` is `darwin`, `linux`, `win32`, or `all` (default).

After that, you'll see the binaries in the `dist` folder :smile:

## FAQ

### Wait, I can do everything with CLI tools without your app !

Yes.

### Why winegold ?

As Jesus turns water into wine, we turn wine into gold.

## Licence
[CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/)
