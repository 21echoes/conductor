# Conductor
An LFO designer for monome norns, grid & crow

LFO is clocked via system
(per-output clock division
 configured in params)

## Norns
K2 stops playback
K3 resumes playback

## Grid
### Grid "zoomed out" page:
* Every 2 rows controls 1 crow output
* 1st row in pair
  * Shows the LFO shape via brightness
  * You can also hold buttons to set start & end points
* 2nd row in pair
  * Left buttons paginate
  * Right button zooms in

### Grid "zoomed in" page:
* Top 7 rows set voltage level
* Last row:
  * Left buttons paginate
  * Middle buttons switch tracks
  * Right button zooms out

Additional per-output params in params menu:
 * enable/disable
 * swing
 * delay
 * slew shape
 * min & max voltage
