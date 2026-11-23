# Smarter Bot Charging

Robot throughput in a big base is rarely limited by robot count. It is limited
by charging: a vanilla roboport has four charging pads, and a robot that decides
to charge commits to one roboport and waits there — even when its pads are all
busy and an idle roboport sits two tiles away. Queues build up, and the base
ends up flying more robots to do the same work.

This mod attacks that from both sides.

**More pads, cheaper flights.** Roboports get 8 charging pads instead of 4, laid
out as an even ring, charging at twice the power. Robots get a larger battery and
lower flight energy, so they reach a roboport less often to begin with. This half
is pure prototype data — no script runs, and it costs nothing at runtime.

**Roboports lend energy to the queue.** When the pads are full, the roboport
pushes energy from its own buffer straight into the robots waiting behind them,
and a roboport that hits its reserve can borrow from the roboports it connects
to. The bottleneck moves off the pad count and onto the power grid, which is
somewhere a factory can actually build its way out of.

Turn on **Show charge queue depth** to see the number of robots waiting above
each congested roboport. It works with lending disabled too, so you can watch
the problem before deciding how hard to fix it.

## What this mod does not do

Robot *dispatch* is engine-side and closed to mods. `robot_order_queue` is
read-only, there is no hook for which robot takes which job, and robots fly in
straight lines with no pathfinding to improve. So no mod can make a robot pick a
closer roboport or a smarter route. This one works on the part that is exposed:
who is queued (`LuaLogisticCell.to_charge_robots`) and how much energy they and
the roboports hold.

## Settings

Startup settings change prototypes and need a restart. The rest can be changed
in a running game.

| Setting | Default | Effect |
| --- | --- | --- |
| Charging pads per roboport | 8 | Robots a roboport charges at once (vanilla 4) |
| Charging power multiplier | 2 | Power per pad, so each charge finishes sooner |
| Robot battery size multiplier | 1.5 | Bigger battery, fewer charge trips |
| Robot flight energy multiplier | 0.75 | Energy spent flying; below 1 is thriftier |
| Roboports lend energy to queued robots | on | The runtime half; off leaves charging to the base game |
| Lending power per robot (MW) | 1 | How fast a queued robot is topped up |
| Roboport energy reserve | 0.2 | Fraction of its buffer a roboport keeps for itself |
| Borrow from neighbouring roboports | on | Congested roboports draw on nearby buffers |
| Robots served per cycle | 200 | UPS budget; serving resumes where it left off |
| Show charge queue depth | off | Overlay of queued robots per roboport |

## Notes

Energy is conserved. A transfer reads back what the robot actually absorbed and
bills the roboport for exactly that, so lending moves energy around rather than
creating it — the draw lands on your power grid.

Personal roboports are left alone by the script. A mobile logistic cell's owner
is the character or vehicle, whose energy is not the equipment grid's, so
draining it would take from the player's armour. They still get the extra
charging pads from the prototype half.

## Building

```
python tools/pack.py SmartBots --deploy
```
