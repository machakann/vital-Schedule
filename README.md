# vital-Schedule

[![Build Status](https://travis-ci.org/machakann/vital-Schedule.svg)](https://travis-ci.org/machakann/vital-Schedule)
[![Build status](https://ci.appveyor.com/api/projects/status/dyjxcv4q9n26v0ep?svg=true)](https://ci.appveyor.com/project/machakann/vital-schedule)


Handling tasks.

# Motivation

When I write a vim plugin, I frequently met a situation that I want to run some operations later. Vim script API gives two choices for the case, autocmd events and timer. However, these measures have quite different interfaces; an autocmd is set by a command `:autocmd` but a timer is controlled by functions. What I want is a unified interface which is easy to handle.

# Task handling

This module provides several objects, and here I introduce `RaceTask` object, it solves the above problem.

For example, it is a little hassle to run an operation only once by using native autocmd interface; if an operation is hooked to autocmd events, the operation should have a code to unset the autocmd events.

```vim
function! s:main() abort
  " do something here

  " set the autocmd event for s:run_once()
  augroup example-augroup
    autocmd!
    autocmd WinLeave * call s:run_once()
  augroup END
endfunction

function! s:run_once() abort
  " do something here

  " unset the autocmd events
  augroup example-augroup
    autocmd! WinLeave
  augroup END
endfunction
```

`RaceTask` makes the situation simpler.

```vim
let s:Schedule = vital#{pluginname}#new().import('Schedule')

function! s:main() abort
  " do sometime here

  " set task
  let task = s:Schedule.RaceTask()
  call task.call(function('s:run_once'), [])
  call task.waitfor(['WinLeave'])
endfunction

function! s:run_once() abort
  " do something here

endfunction
```

Moreover, it can accept multiple triggers. For example, if you want to run a function after 3000 milliseconds passed or when user stars editing:

```vim
let s:Schedule = vital#{pluginname}#new().import('Schedule')

function! s:main() abort
  " do sometime here

  " set task
  let task = s:Schedule.RaceTask()
  call task.call(function('s:run_once'), [])
  call task.waitfor([3000, 'TextChanged', 'TextChangedI'])
endfunction

function! s:run_once() abort
  " do something here

endfunction
```

`s:run_once()` will be triggered by the earliest one in 3000 milliseconds, `TextChanged` or `TextChangedI`. Replace `{pluginname}` with your plugin name.

# License: NYSL license
  * [Japanese](http://www.kmonos.net/nysl/)
  * [English (Unofficial)](http://www.kmonos.net/nysl/index.en.html)


