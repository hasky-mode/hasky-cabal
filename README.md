# Hasky Cabal

[![License GPL 3](https://img.shields.io/badge/license-GPL_3-green.svg)](http://www.gnu.org/licenses/gpl-3.0.txt)
[![MELPA](https://melpa.org/packages/hasky-cabal-badge.svg)](https://melpa.org/#/hasky-cabal)
[![Build Status](https://travis-ci.org/hasky-mode/hasky-cabal.svg?branch=master)](https://travis-ci.org/hasky-mode/hasky-cabal)

This is an Emacs interface to the [Cabal](https://www.haskell.org/cabal/)
Haskell development tool.

## Installation

Download this package and place it somewhere, so Emacs can see it. Then put
`(require 'hasky-cabal)` into your configuration file. Done!

It's available via MELPA, so you can just <kbd>M-x package-install RET
hasky-cabal</kbd>.

## Usage

Bind the following useful commands:

```emacs-lisp
(global-set-key (kbd "<next> h e") #'hasky-cabal-execute)
(global-set-key (kbd "<next> h h") #'hasky-cabal-package-action)
```

* `hasky-cabal-execute` opens a popup with a collection of Cabal commands
  you can run. Many commands have their own sub-popups like in Magit.

* `hasky-cabal-package-action` allows to perform actions on package that the
  user selects from the list of all available packages.

## Switchable variables

There is a number of variables that control various aspects of the package.
They can be set with `setq` or via the customization mechanisms. This way
one can change their default values. However, sometimes it's desirable to
quickly toggle the variables and it's possible to do directly from the popup
menus: just hit the key displayed under the “variables” section.

Switchable variables include:

* `hasky-cabal-auto-target`—whether to automatically select the default
  build target (build sub-popup).
* `hasky-cabal-auto-open-coverage-reports`—whether to attempt to
  automatically open coverage report in browser (build sub-popup).
* `hasky-cabal-auto-open-haddocks`—whether to attempt to automatically open
  Haddocks in browser (build sub-popup).
* `hasky-cabal-auto-newest-version`—whether to install newest version of
  package without asking (package action popup).

## Customization

There is a number of customization options that are available via <kbd>M-x
customize-group hasky-cabal</kbd>.

## License

Copyright © 2018 Mark Karpov

Distributed under GNU GPL, version 3.
