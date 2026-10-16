extends Node
## EventBus — global "something already happened" fan-out between systems.
##
## S0.3 batch 1.  Deliberately **stateless**: signals only — no fields, no methods.
## The moment this node holds data it becomes a second `GameState`, and every
## subscriber can then reach the whole game through the bus.
##
## NAMING (ROADMAP §3.2).  Three prefixes are reserved for controls and state:
## `on_xxx` (a button was pressed), `xxx_changed` (a value changed), `xxx_requested`
## (someone asks for an action).  Facts that have **already happened** use the past
## tense `<subject>_<past_participle>` — that is the family below.  A listener must
## therefore never be asked to *approve* anything through this bus: a request is not
## an event, and a request sent here would have no way to answer.
##
## PAYLOADS ARE PLAIN DATA.  Dictionaries travel by reference, so an emitter must
## pass a fresh copy, never a live internal structure — otherwise one listener's
## edit silently rewrites another's input.
##
## ⚠️ Signal connections live as long as the process.  Any node connecting here MUST
## disconnect in `_exit_tree()` (or connect with `CONNECT_ONE_SHOT`); otherwise a
## freed node keeps getting called.  That autoload leak is why `s0_3_state` asserts
## this contract instead of trusting call sites.

## A logical step of in-game time has passed.  `day` is 1-based; `time_of_day` runs
## 0.0..1.0 with 0 = midnight, the same convention as `DayNight.time_of_day`.
## S0.3 announces one tick per in-game hour; S1.4 adds whatever finer cadence the
## calendar needs.
signal time_advanced(day: int, time_of_day: float)

## The party ran into something that needs resolving (M1 S1.6 owns the payload).
signal encounter_started(ctx: Dictionary)

## A battle resolved.  S0.3 only forwards `result`; M2 owns its shape.
signal battle_finished(result: Dictionary)

## Money / food / supply changed.  Carries the **new values**, not a delta, so a
## listener never has to know the previous state to render a number.
signal resources_changed(money: int, food: int, supply: int)

## The party entered a settlement (M1 S1.7); `settlement_id` is a stable id.
signal settlement_entered(settlement_id: String)