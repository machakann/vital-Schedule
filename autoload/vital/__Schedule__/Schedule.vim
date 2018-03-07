" TODO: Implement NeatTask.preprocess()/.postprocess()
" TODO: Support [nested]
let s:TRUE = 1
let s:FALSE = 0
let s:ON = 1
let s:OFF = 0
let s:DEFAULTAUGROUP = 'vital-Schedule'

" Class system {{{
function! s:inherit(sub, super, ...) abort "{{{
  if a:0 == 0
    return s:_inherit(a:sub, a:super)
  endif
  let super = a:000[-1]
  let itemlist = [a:super] + a:000[:-2]
  for item in reverse(itemlist)
    let super = s:_inherit(item, super)
  endfor
  return s:_inherit(a:sub, super)
endfunction "}}}

function! s:super(sub, ...) abort "{{{
  if !has_key(a:sub, '__SUPER__')
    return {}
  endif

  let supername = get(a:000, 0, a:sub.__SUPER__.__CLASS__)
  let supermethods = a:sub
  try
    while supermethods.__CLASS__ isnot# supername
      let supermethods = supermethods.__SUPER__
    endwhile
  catch /^Vim\%((\a\+)\)\=:E716/
    echoerr printf('%s class does not have the super class named %s', a:sub.__CLASS__, supername)
  endtry

  let super = {}
  for [key, l:Val] in items(supermethods)
    if type(l:Val) is v:t_func
      let super[key] = function('s:_supercall', [a:sub, l:Val])
    endif
  endfor
  return super
endfunction "}}}

function! s:supercall(sub, supername, funcname) abort "{{{
  if !has_key(a:sub, '__SUPER__')
    return
  endif

  let supermethods = a:sub
  try
    while supermethods.__CLASS__ isnot# a:supername
      let supermethods = supermethods.__SUPER__
    endwhile
  catch /^Vim\%((\a\+)\)\=:E716/
    echoerr printf('%s class does not have the super class named %s', a:sub.__CLASS__, a:supername)
  endtry

  let args = get(a:000, 0, [])
  return s:_supercall(supermethods[a:funcname], args, a:sub)
endfunction "}}}

function! s:_inherit(sub, super) abort "{{{
  call extend(a:sub, a:super, 'keep')
  let a:sub.__SUPER__ = {}
  let a:sub.__SUPER__.__CLASS__ = a:super.__CLASS__
  for [key, l:Val] in items(a:super)
    if type(l:Val) is v:t_func || key is# '__SUPER__'
      let a:sub.__SUPER__[key] = l:Val
    endif
  endfor
  return a:sub
endfunction "}}}

function! s:_supercall(sub, Funcref, ...) abort "{{{
  return call(a:Funcref, a:000, a:sub)
endfunction "}}}
"}}}

" Error list {{{
function! s:InvalidTriggers(triggerlist) abort "{{{
  return printf('vital-Schedule:E1: Invalid triggers, %s',
              \ string(a:triggerlist))
endfunction "}}}
"}}}



" Event class {{{
let s:Event = {
  \   'table': {},
  \ }

function! s:Event.add(augroup, event, pat, task) abort "{{{
  if !has_key(self.table, a:augroup)
    let self.table[a:augroup] = {}
  endif
  if !has_key(self.table[a:augroup], a:event)
    let self.table[a:augroup][a:event] = {}
  endif
  if !has_key(self.table[a:augroup][a:event], a:pat)
    let self.table[a:augroup][a:event][a:pat] = []
    call s:_autocmd(a:augroup, a:event, a:pat)
  endif
  call add(self.table[a:augroup][a:event][a:pat], a:task)
endfunction "}}}

function! s:Event.remove(augroup, event, pat, task) abort "{{{
  if !has_key(s:Event.table, a:augroup) || !has_key(s:Event.table[a:augroup], a:event)
      \ || !has_key(s:Event.table[a:augroup][a:event], a:pat)
    return
  endif

  call filter(self.table[a:augroup][a:event][a:pat], 'v:val isnot a:task')
  call s:_sweep(a:augroup, a:event, a:pat)
endfunction "}}}

function! s:_autocmd(augroup, event, pat) abort "{{{
  let autocmd = printf("autocmd %s %s call s:_doautocmd('%s', '%s', '%s')",
                      \ a:event, a:pat, a:augroup, a:event, a:pat)

  execute 'augroup ' . a:augroup
    execute autocmd
  augroup END
endfunction "}}}

function! s:_doautocmd(augroup, event, pat) abort "{{{
  if !has_key(s:Event.table, a:augroup) || !has_key(s:Event.table[a:augroup], a:event)
      \ || !has_key(s:Event.table[a:augroup][a:event], a:pat)
    return
  endif

  for task in s:Event.table[a:augroup][a:event][a:pat]
    call task.trigger()
  endfor
  call s:_sweep(a:augroup, a:event, a:pat)
endfunction "}}}

function! s:_sweep(augroup, event, pat) abort "{{{
  if !has_key(s:Event.table, a:augroup) || !has_key(s:Event.table[a:augroup], a:event)
      \ || !has_key(s:Event.table[a:augroup][a:event], a:pat)
    return
  endif

  call filter(s:Event.table[a:augroup][a:event][a:pat], '!v:val.hasdone()')
  if empty(s:Event.table[a:augroup][a:event][a:pat])
    execute printf('autocmd! %s %s %s', a:augroup, a:event, a:pat)
    call remove(s:Event.table[a:augroup][a:event], a:pat)
  endif
  if empty(s:Event.table[a:augroup][a:event])
    call remove(s:Event.table[a:augroup], a:event)
  endif
  if empty(s:Event.table[a:augroup])
    call remove(s:Event.table, a:augroup)
  endif
endfunction "}}}
"}}}



" Timer class {{{
let s:Timer = {
  \   'table': {},
  \ }

function! s:Timer.add(time, task) abort "{{{
  let id = timer_start(a:time, function('s:_timercall'), {'repeat': -1})
  let self.table[string(id)] = a:task
  return id
endfunction "}}}

function! s:Timer.remove(id) abort "{{{
  let idstr = string(a:id)
  if has_key(self.table, idstr)
    call remove(self.table, idstr)
  endif
  if !empty(timer_info(a:id))
    call timer_stop(a:id)
  endif
endfunction "}}}

function! s:_timercall(id) abort "{{{
  if !has_key(s:Timer.table, string(a:id))
    return
  endif
  let timertask = s:Timer.table[string(a:id)]
  call timertask.trigger()
endfunction "}}}
"}}}



" Switch class {{{
unlockvar! s:Switch
let s:Switch = {
  \ '__CLASS__': 'Switch',
  \ '__switch__': {
  \   'skipcount': 0,
  \   'skipif': [],
  \   }
  \ }
function! s:Switch() abort "{{{
  return deepcopy(s:Switch)
endfunction "}}}

function! s:Switch._on() abort "{{{
  let self.__switch__.skipcount = 0
  return self
endfunction "}}}

function! s:Switch._off() abort "{{{
  let self.__switch__.skipcount = -1
  return self
endfunction "}}}

function! s:Switch.skip(...) abort "{{{
  let self.__switch__.skipcount = max([get(a:000, 0, 1), -1])
  return self
endfunction "}}}

function! s:Switch.skipif(func, args, ...) abort "{{{
  let self.__switch__.skipif = [a:func, a:args] + a:000
endfunction "}}}

function! s:Switch._isactive() abort "{{{
  if !empty(self.__switch__.skipif)
    if call('call', self.__switch__.skipif)
      return s:FALSE
    endif
  endif
  return self.__switch__.skipcount == 0
endfunction "}}}

function! s:Switch._skipsthistime() abort "{{{
  if self._isactive()
    return s:FALSE
  endif
  if self.__switch__.skipcount > 0
    let self.__switch__.skipcount -= 1
    if self.__switch__.skipcount == 0
      call self._on()
    endif
  endif
  return s:TRUE
endfunction "}}}

lockvar! s:Switch
"}}}



" Counter class {{{
unlockvar! s:Counter
let s:Counter = {
  \ '__CLASS__': 'Counter',
  \ '__counter__': {
  \   'repeat': 1,
  \   'done': 0,
  \   'finishif': [],
  \   }
  \ }
function! s:Counter(count) abort "{{{
  let counter = deepcopy(s:Counter)
  let counter.__counter__.repeat = a:count
  return counter
endfunction "}}}

function! s:Counter.repeat(...) abort "{{{
  if a:0 > 0
    let self.__counter__.repeat = a:1
  endif
  let self.__counter__.done = 0
  return self
endfunction "}}}

function! s:Counter._tick(...) abort "{{{
  let self.__counter__.done += get(a:000, 0, 1)
endfunction "}}}

function! s:Counter.leftcount() abort "{{{
  if self.__counter__.repeat < 0
    return -1
  endif
  return max([self.__counter__.repeat - self.__counter__.done, 0])
endfunction "}}}

function! s:Counter.hasdone() abort "{{{
  if self.leftcount() == 0
    return s:TRUE
  endif

  " 'finishif' check
  if !empty(self.__counter__.finishif)
    if call('call', self.__counter__.finishif)
      return s:TRUE
    endif
  endif

  return s:FALSE
endfunction "}}}

function! s:Counter.finishif(func, args, ...) abort "{{{
  let self.__counter__.finishif = [a:func, a:args] + a:000
endfunction "}}}

lockvar! s:Counter
"}}}



" Task class {{{
unlockvar! s:Task
let s:Task = {
  \ '__CLASS__': 'Task',
  \ '_orderlist': [],
  \ }
function! s:Task() abort "{{{
  return deepcopy(s:Task)
endfunction "}}}

function! s:Task.trigger() abort "{{{
  for [kind, expr] in self._orderlist
    if kind is# 'call'
      call call('call', expr)
    elseif kind is# 'execute'
      execute expr
    elseif kind is# 'task'
      call expr.trigger()
    endif
  endfor
  return self
endfunction "}}}

function! s:Task.call(func, args, ...) abort "{{{
  let order = ['call', [a:func, a:args] + a:000]
  call add(self._orderlist, order)
  return self
endfunction "}}}

function! s:Task.execute(cmd) abort "{{{
  let order = ['execute', a:cmd]
  call add(self._orderlist, order)
  return self
endfunction "}}}

function! s:Task.append(task) abort "{{{
  let order = ['task', a:task]
  call add(self._orderlist, order)
  return self
endfunction "}}}

function! s:Task.clear() abort "{{{
  call filter(self._orderlist, 0)
  return self
endfunction "}}}

function! s:Task.clone() abort "{{{
  let clone = deepcopy(self)
  let clone._orderlist = copy(self._orderlist)
  return clone
endfunction "}}}

lockvar! s:Task
"}}}



" NeatTask class (inherits Switch, Counter and Task classes) {{{
unlockvar! s:NeatTask
let s:NeatTask = {
  \ '__CLASS__': 'NeatTask',
  \ }
function! s:NeatTask() abort "{{{
  let switch = s:Switch()
  let counter = s:Counter(1)
  let task = s:Task()
  let neattask = deepcopy(s:NeatTask)
  return s:inherit(neattask, task, counter, switch)
endfunction "}}}

function! s:NeatTask.trigger() abort "{{{
  if self._skipsthistime()
    return self
  endif
  if self.hasdone()
    return self
  endif
  call s:super(self, 'Task').trigger()
  call self._tick()
  if self.hasdone()
    call self.cancel()
  endif
  return self
endfunction "}}}

function! s:NeatTask.waitfor() abort "{{{
  return self
endfunction "}}}

function! s:NeatTask.cancel() abort "{{{
  return self
endfunction "}}}

function! s:NeatTask.isactive() abort "{{{
  return self._isactive()
endfunction "}}}

lockvar! s:NeatTask
"}}}



" TimerTask class (inherits NeatTask class) {{{
unlockvar! s:TimerTask
let s:TimerTask = {
  \ '__CLASS__': 'TimerTask',
  \ '_id': -1,
  \ '_time': 0,
  \ '_state': s:OFF,
  \ }
function! s:TimerTask() abort "{{{
  let neattask = s:NeatTask()
  let timertask = deepcopy(s:TimerTask)
  return s:inherit(timertask, neattask)
endfunction "}}}

function! s:TimerTask.clone() abort "{{{
  let clone = s:TimerTask()
  let clone.__switch__ = deepcopy(self.__switch__)
  let clone.__counter__ = deepcopy(self.__counter__)
  let clone.__timer__.id = -1
  let clone._state = s:OFF
  let clone._orderlist = copy(self._orderlist)
  return clone
endfunction "}}}

function! s:TimerTask.waitfor(time) abort "{{{
  call self.cancel().repeat()
  if self.leftcount() == 0 || a:time <= 0
    return self
  endif

  let self._state = s:ON
  let self._time = a:time
  let self._id = s:Timer.add(a:time, self)
  return self
endfunction "}}}

function! s:TimerTask.cancel() abort "{{{
  let self._state = s:OFF
  if self._id < 0
    return self
  endif

  call s:Timer.remove(self._id)
  let self._id = -1
  return self
endfunction "}}}

function! s:TimerTask.isactive() abort "{{{
  return self._state && s:super(self, 'Switch')._isactive()
endfunction "}}}

function! s:TimerTask._getid() abort "{{{
  " a method for test
  return self._id
endfunction "}}}

lockvar! s:TimerTask
"}}}



" EventTask class (inherits NeatTask class) {{{
unlockvar! s:EventTask
let s:EventTask = {
  \ '__CLASS__': 'EventTask',
  \ '_augroup': '',
  \ '_event': '',
  \ '_pat': '',
  \ '_state': s:OFF,
  \ }
function! s:EventTask(...) abort "{{{
  let neattask = s:NeatTask()
  let eventtask = s:inherit(deepcopy(s:EventTask), neattask)
  let eventtask._augroup = get(a:000, 0, s:DEFAULTAUGROUP)
  return eventtask
endfunction "}}}

function! s:EventTask.clone() abort "{{{
  let clone = s:EventTask()
  let clone.__switch__ = deepcopy(self.__switch__)
  let clone.__counter__ = deepcopy(self.__counter__)
  let clone._event = ''
  let clone._state = s:OFF
  let clone._orderlist = copy(self._orderlist)
  return clone
endfunction "}}}

function! s:EventTask.waitfor(eventexpr) abort "{{{
  call self.cancel().repeat()
  if self.leftcount() == 0
    return self
  endif
  let augroup = self._augroup
  let [event, pat] = s:event_and_patterns(a:eventexpr)

  let self._state = s:ON
  let self._event = event
  let self._pat = pat
  call s:Event.add(augroup, event, pat, self)
  return self
endfunction "}}}

function! s:EventTask.cancel() abort "{{{
  let self._state = s:OFF
  let augroup = self._augroup
  let event = self._event
  let pat = self._pat
  call s:Event.remove(augroup, event, pat, self)
  return self
endfunction "}}}

function! s:EventTask.isactive() abort "{{{
  return self._state && s:super(self, 'Switch')._isactive()
endfunction "}}}

lockvar! s:EventTask
"}}}



" RaceTask class (inherits NeatTask class) {{{
unlockvar! s:RaceTask
let s:RaceTask = {
  \ '__CLASS__': 'RaceTask',
  \ '__racetask__': {
  \   'Event': [],
  \   'Timer': -1,
  \   },
  \ '_state': s:OFF,
  \ '_augroup': '',
  \ }
function! s:RaceTask(...) abort "{{{
  let neattask = s:NeatTask()
  let racetask = s:inherit(deepcopy(s:RaceTask), neattask)
  let racetask._augroup = get(a:000, 0, s:DEFAULTAUGROUP)
  return racetask
endfunction "}}}

function! s:RaceTask.clone() abort "{{{
  let clone = s:RaceTask()
  let clone.__switch__ = deepcopy(self.__switch__)
  let clone.__counter__ = deepcopy(self.__counter__)
  let clone._state = s:OFF
  let clone._orderlist = copy(self._orderlist)
  return clone
endfunction "}}}

function! s:RaceTask.waitfor(triggerlist) abort "{{{
  call self.cancel().repeat()
  let invalid = s:invalid_triggerlist(a:triggerlist)
  if !empty(invalid)
    echoerr s:InvalidTriggers(invalid)
  endif
  let augroup = self._augroup

  let self._state = s:ON
  let events = filter(copy(a:triggerlist), 'type(v:val) is v:t_string || type(v:val) is v:t_list')
  call uniq(sort(events))
  for eventexpr in events
    let [event, pat] = s:event_and_patterns(eventexpr)
    call s:Event.add(augroup, event, pat, self)
    call add(self.__racetask__.Event, [event, pat])
  endfor

  let times = filter(copy(a:triggerlist), 'type(v:val) is v:t_number')
  call filter(times, 'v:val > 0')
  if !empty(times)
    let time = min(times)
    let self.__racetask__.Timer = s:Timer.add(time, self)
  endif
  return self
endfunction "}}}

function! s:RaceTask.cancel() abort "{{{
  let self._state = s:OFF
  if !empty(self.__racetask__.Event)
    let augroup = self._augroup
    for [event, pat] in self.__racetask__.Event
      call s:Event.remove(augroup, event, pat, self)
    endfor
    call filter(self.__racetask__.Event, 0)
  endif
  if self.__racetask__.Timer != -1
    let id = self.__racetask__.Timer
    call s:Timer.remove(id)
    let self.__racetask__.Timer = -1
  endif
  return self
endfunction "}}}

function! s:RaceTask.isactive() abort "{{{
  return self._state && s:super(self, 'Switch')._isactive()
endfunction "}}}

function! s:RaceTask._getid() abort "{{{
  return self.__racetask__.Timer
endfunction "}}}

lockvar! s:RaceTask
"}}}



" TaskChain class (inherits Counter class) {{{
unlockvar! s:TaskChain
let s:TaskChain = {
  \ '__CLASS__': 'TaskChain',
  \ '_index': 0,
  \ '_triggerlist': [],
  \ '_orderlist': [],
  \ '_augroup': '',
  \ '_state': s:OFF,
  \ }
function! s:TaskChain(...) abort "{{{
  let counter = s:Counter(1)
  let taskchain = s:inherit(deepcopy(s:TaskChain), counter)
  let taskchain._augroup = get(a:000, 0, s:DEFAULTAUGROUP)
  return taskchain
endfunction "}}}

function! s:TaskChain.event(event) abort "{{{
  let eventtask = s:EventTask(self._augroup)
  let ordertask = s:NeatTask()
  let args = [a:event]
  call self._settrigger(eventtask, args)
  call self._setorder(ordertask)
  return ordertask
endfunction "}}}

function! s:TaskChain.timer(time) abort "{{{
  let timertask = s:TimerTask()
  let ordertask = s:NeatTask()
  call self._settrigger(timertask, [a:time])
  call self._setorder(ordertask)
  return ordertask
endfunction "}}}

function! s:TaskChain.race(triggerlist) abort "{{{
  let invalid = s:invalid_triggerlist(a:triggerlist)
  if !empty(invalid)
    echoerr s:InvalidTriggers(invalid)
  endif

  let racetask = s:RaceTask(self._augroup)
  let ordertask = s:NeatTask()
  let args = [a:triggerlist]
  call self._settrigger(racetask, args)
  call self._setorder(ordertask)
  return ordertask
endfunction "}}}

function! s:TaskChain.trigger() abort "{{{
  if self._index >= len(self._orderlist)
    return self
  endif

  let task = self._orderlist[self._index]
  call task.trigger()
  if self.hasdone()
    call self.cancel()
  elseif task.hasdone()
    call self._gonext()
  endif
  return self
endfunction "}}}

function! s:TaskChain.waitfor() abort "{{{
  call self.cancel().repeat()
  let self._state = s:ON
  let [trigger, args] = self._triggerlist[self._index]
  call call(trigger.waitfor, args, trigger)
  return self
endfunction "}}}

function! s:TaskChain.cancel() abort "{{{
  let self._state = s:OFF
  if self._index == len(self._orderlist)
    return self
  endif
  let [trigger, _] = self._triggerlist[self._index]
  let task = self._orderlist[self._index]
  call trigger.cancel()
  call task.cancel()
  return self
endfunction "}}}

function! s:TaskChain._settrigger(triggertask, args) abort "{{{
  call a:triggertask.repeat(-1)
  call a:triggertask.call(self.trigger, [], self)
  call add(self._triggerlist, [a:triggertask, a:args])
endfunction "}}}

function! s:TaskChain._setorder(ordertask) abort "{{{
  call a:ordertask.repeat(1)
  call add(self._orderlist, a:ordertask)
endfunction "}}}

function! s:TaskChain._gonext() abort "{{{
  let [trigger, _] = self._triggerlist[self._index]
  call trigger.cancel()

  let self._index += 1
  if self._index == len(self._orderlist)
    call self._tick()
    if self.hasdone()
      call self.cancel()
      return
    else
      let self._index = 0
    endif
  endif
  let [nexttrigger, args] = self._triggerlist[self._index]
  call call(nexttrigger.waitfor, args, nexttrigger)
endfunction "}}}

lockvar! s:TaskChain
"}}}



function! s:event_and_patterns(eventexpr) abort "{{{
  let t_event = type(a:eventexpr)
  if t_event is v:t_string
    let event = a:eventexpr
    let pat = '*'
  elseif t_event is v:t_list
    let event = a:eventexpr[0]
    let pat = get(a:eventexpr, 1, '*')
  else
    echoerr s:InvalidTriggers(a:eventexpr)
  endif
  return [event, pat]
endfunction "}}}

function! s:invalid_triggerlist(triggerlist) abort "{{{
  return filter(copy(a:triggerlist), '!s:isvalidtriggertype(v:val)')
endfunction "}}}

function! s:isvalidtriggertype(item) abort "{{{
  let t_trigger = type(a:item)
  if t_trigger is v:t_string || t_trigger is v:t_list || t_trigger is v:t_number
    return s:TRUE
  endif
  return s:FALSE
endfunction "}}}

function! s:augroup(name) dict abort "{{{
  let new = deepcopy(self)
  let new.EventTask = funcref(self.EventTask, [a:name])
  let new.RaceTask = funcref(self.RaceTask, [a:name])
  let new.TaskChain = funcref(self.TaskChain, [a:name])
  return new
endfunction "}}}

" vim:set foldmethod=marker:
" vim:set commentstring="%s:
" vim:set et ts=2 sw=2 sts=-1:
