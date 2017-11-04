<p align="center">
  <img src="icon/logo.svg" height="130">
  <h3 align="center">winegold</h3>
  <p align="center">An open-source drag and drop tool built with web technology<p>
  <p align="center"><a href="https://github.com/sindresorhus/xo"><img src="https://img.shields.io/badge/code_style-XO-5ed9c7.svg" alt="XO code style"></a></p>
</p>

**This tool is a WIP, he is not really usable right now.**

## Use winegold

![demo of winegold app](test/demo.gif)

Yes, I expected to be simple as this example.

One drag and drop, detecting what to do with this file. Or asking what you want to do with the files you've just dragged.

### What you can do with winegold

- Convert a file in multiple formats
- Process multiple files
- Use autolaunch feature to make a "one move drag and drop" easier than ever
- Convert your old shell script to a nice trigger who writes output in a file.
- Read content of a file and use it to do evil :see_no_evil:
- Use JavaScript or bash (equal everything!), what is your favorite flavor ?
- [Create your own scripts](docs/scripts.md) to use you drag and drop box

### What we want to do

**This is a wanted feature**

Does anything possible and create a way to handle conversion cli tools (like [Calibre ebook-convert](ebook-convert), [ImageMagick](https://github.com/ImageMagick/ImageMagick)) into a multi-platform downloadable dependency on the need.

If you want to convert a kind of file, dependencies are downloaded if you need, and your file is processed.

### Everything is scripting

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

[Read the script documentation](docs/script.md)

## Get winegold

**This tool is a WIP, he is not really usable right now.**

The app work on macOS, but drag and drop doesn't work on Windows after few test. If someone want to fix that :smile:


## Contribute

### Requirement

Use Eslint/XO syntax (xo --fix is used when you make `yarn test`. You can install it like this:

```
npm install xo -g
```

It is strongly recommended to use yarn instead of npm to build the app, [electron-builder](https://github.com/electron-userland/electron-builder) is nicer with him. [You can install it by following this link](https://yarnpkg.com/lang/en/docs/install/).


### Run the app
- [Fork](https://help.github.com/articles/fork-a-repo/) this repository to your own GitHub account and then [clone](https://help.github.com/articles/cloning-a-repository/) it to your local device
- Install the dependencies:

```
yarn
```
- Build the code and watch for changes:

```
yarn test
```
### Build the app

To make sure that your code works in the finished app, you can generate the binary:

```
yarn dist
```

After that, you'll see the binary in the `dist` folder :smile:
