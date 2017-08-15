extensions [ gis ]

breed [households household]
breed [villages village]
households-own [field-max fed-prop grain-supply fuzzy-yield fuzzy-return occupants farm-fields]
villages-own [settled-patches]
patches-own [settlement patch-yield slope-val soil-depth vegetation fertility farmstead state field owner fallow site]
globals [cost-raster slope-raster wood-gather-intensity starvation-threshold birth-rate death-rate patches-per-m2 max-capita-labor max-farm-dist max-wood-dist max-yield seed-prop max-veg fertility-loss-rate max-fallow fertility-restore-rate]

to setup
  clear-all
  set max-veg 50
  set seed-prop .15
  set max-capita-labor 250
  set patches-per-m2 patches-per-ha / 10000
  set max-farm-dist 75 * sqrt(patches-per-ha)
  set max-wood-dist 150 * sqrt(patches-per-ha)
  set max-yield 3500 / patches-per-ha
  set birth-rate 0.054
  set death-rate 0.04
  set starvation-threshold 0.6
  set wood-gather-intensity 0.08
  ;setup-gis
  setup-patches
  setup-village

  reset-ticks
end

to setup-gis
  set cost-raster gis:load-dataset "cost.asc"
  gis:set-world-envelope gis:envelope-of cost-raster
  ;gis:apply-raster cost-raster cost

  set slope-raster gis:load-dataset "slope.asc"
  gis:apply-raster slope-raster slope-val
end

to setup-patches
  ask patches [
    set slope-val 1
    set soil-depth 1
    set vegetation 50
    set pcolor 52
    set field 0
    set fertility 100
    set owner nobody
    ;set fallow 0
    set site FALSE
    set farmstead 0
    set settlement 0
    set patch-yield 0
  ]
end


to setup-village
  create-villages 1 [
   ht
    ;move-to patch 519 345
    hatch-households init-households [
      set fuzzy-yield [yield "wheat"] of one-of patches in-radius 5 with [fertility > 0]
      set occupants 6
      set grain-supply occupants * grain-req
      set farm-fields no-patches
      set fed-prop 1
      set field-max floor ((occupants * max-capita-labor) / 40) * patches-per-ha
      ht
    ]
    let settled-area max list 1 round(.175 * (sum [occupants] of households-here) ^ .634 * patches-per-ha)
    set settled-patches min-n-of settled-area patches [distance myself]
    ask settled-patches [
      set pcolor red
      set owner myself
      set settlement 1
      set vegetation 0
      set patch-yield 0
    ]
  ]
end


to go
  ;if max-cycles > 0 and ticks >= max-cycles [ stop ]

  ask households [
    check-farmland
  ]

  ask households [
    farm
    gather-wood
  ]

  if dynamic-pop [birth-death]


  regrow-patch
  tick
end

to check-farmland
  let field-req  round ((occupants * grain-req * (1 + seed-prop)) / (fuzzy-yield * expectation-scalar))
  ;set field-req field-req - round (fuzzy-return / fuzzy-yield)


  set field-req (min list field-req field-max)
  ifelse tenure = "none"
  [ if count farm-fields > 0 [ drop-farmland (count farm-fields) ]
    choose-farmland (field-req)]
  [ if field-req < count farm-fields
      [ drop-farmland (count farm-fields - field-req) ]
    if field-req > count farm-fields and any? other patches with [fertility > 0 and owner = nobody]
      [ choose-farmland (field-req - count farm-fields) ]
  ]
end

to drop-farmland [num-fields]
 let mean-yield mean [patch-yield] of farm-fields
  let max-patch-yield max [patch-yield] of farm-fields
  let drop-fields ifelse-value (tenure = "maximizing")
    [farm-fields with [patch-yield < (max-patch-yield * (1 - tenure-drop))] ]
   [n-of num-fields farm-fields]

  ask drop-fields [
    set owner nobody
    set patch-yield 0
    set field 0
    set pcolor 59.9 - (vegetation * 7.9 / 50)
  ]
  set farm-fields farm-fields with [owner = myself]
end

to choose-farmland [num-fields]
  let new-fields max-n-of num-fields patches with [owner = nobody] [farm-val]
  ;let patch-clear 0
  ask new-fields [
    set owner myself
    set field 1
    set vegetation 5
  ]

  ;set cleared-wood cleared-wood + patch-clear
  ;ask n-of (num-fields / 2) new-fields [ set fallow 1 ]
  set farm-fields (patch-set farm-fields new-fields)
end

to-report farm-val
  ;let lcdeval (ifelse-value (vegetation <= 30) [ vegetation * 25 / 30 ] [ vegetation * 65 / 20 - 72.5 ]) / 100
  report slope-val * (((fertility / 100 + 1) * (soil-depth + 1)) / 2) - (1 * (distance myself) / max-farm-dist) ;+ lcdeval)
end

to-report yield [crop]
  ifelse crop = "wheat"
    [ let potential-yield (((0.51 * ln(annual-precip)) + 1.03) * ((0.28 * ln(soil-depth)) + 0.87) * ((0.19 * ln(fertility / 100)) + 1)) / 3
      report (potential-yield * slope-val * max-yield) / patches-per-ha ]
    [ report 0 ]
end

to farm
  ask farm-fields [
    set fallow 0
    set field 1

    ifelse fertility > 0
      [ set patch-yield yield "wheat"
        set fertility (fertility - random-normal 3 2)]
    [set patch-yield 0]
    if fertility < 0 [set fertility 0]
    set pcolor 39.9 - (8.9 * fertility / 100)
   ]

  let gross-return sum [patch-yield] of farm-fields
  set fed-prop gross-return * (1 - seed-prop) / (grain-req * occupants)
  let net-return gross-return * (1 - seed-prop) - (grain-req * occupants)

  set grain-supply grain-supply + net-return
  if grain-supply < 0 [ set grain-supply 0 ]

  set fuzzy-return random-normal net-return abs(net-return * .0333)

  let mean-yield mean [patch-yield] of farm-fields
  set fuzzy-yield random-normal mean-yield (mean-yield * .0333)
end


to gather-wood
  let num-patches round(occupants * wood-req / (wood-gather-intensity / patches-per-m2))
  let wood-patches max-n-of num-patches patches with [vegetation >= 9] [ ((vegetation - 9) / 41 + (3 * (1 - (distance myself / max-wood-dist)))) / (1 + 3) ]
  ask wood-patches [
      ifelse vegetation > 35
      [ set vegetation ((vegetation * .0806 - 2.08) - wood-gather-intensity + 2.08) / .0806 ]
      [ ifelse vegetation > 18
        [ set vegetation ((vegetation * .0047 + .5755) - wood-gather-intensity - .5755) / .0047 ]
        [ set vegetation ((vegetation * .0509 - .2562) - wood-gather-intensity + .2562) / .0509 ]]
      if vegetation < 0 [ set vegetation 0 ]
  ]

end


to birth-death
  ask households [
   let deaths (random-poisson (death-rate * 100)) / 100 * occupants
  let births ifelse-value (fed-prop >= starvation-threshold)
[ (random-poisson (birth-rate * 100)) / 100 * occupants ]
[ 0 ]

  if (births - deaths != 0)  [
  set occupants occupants + births - deaths

  if occupants <= 0 [ die ]
  set field-max floor ((occupants * max-capita-labor) / 40) * patches-per-ha
  ]
  ]

  ask villages [
    let settled-area max list 1 round(.175 * (sum [occupants] of households-here) ^ .634 * patches-per-ha)
    if settled-area != count settled-patches [adjust-settlement-size (settled-area - count settled-patches)]
  ]

end

to adjust-settlement-size [patch-diff]
  ifelse patch-diff > 0
    [repeat patch-diff [
      ask min-one-of patches with [any? neighbors4 with [settlement = 1]] [farm-val][
        set owner myself
        set pcolor red
        set settlement 1
        set field 0
        set vegetation 0
        set patch-yield 0]]]
    [ask max-n-of abs(patch-diff) settled-patches [distance myself]
     [set owner nobody
      set settlement 0
      set pcolor 59.9 - (vegetation * 7.9 / 50)]]
  set settled-patches patches with [owner = myself]
end

to regrow-patch
  ask patches [

    if fertility < 100 [set fertility fertility + random-normal 2 .5 ]
    if fertility > 100 [set fertility 100]

    if field = 0 and settlement = 0 [
      if vegetation < max-veg [
        let regrowth-rate (((-0.000118528 * fertility ^ 2) + (0.0215056 * fertility) + 0.0237987) + ((-0.000118528 * soil-depth ^ 2) + (0.0215056 * soil-depth) + 0.0237987)) / 2
        set vegetation vegetation + regrowth-rate
        if vegetation > max-veg [set vegetation max-veg]
        set pcolor 59.9 - (vegetation * 7.9 / 50)
      ]

    ]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
286
10
785
510
-1
-1
2.443
1
10
1
1
1
0
0
0
1
-100
100
-100
100
1
1
1
ticks
30.0

BUTTON
7
12
80
45
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
83
12
146
45
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
83
58
147
91
step
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
17
230
189
263
init-households
init-households
0
50
10.0
1
1
NIL
HORIZONTAL

SLIDER
3
98
203
131
grain-req
grain-req
140
250
212.0
1
1
kg/person
HORIZONTAL

SLIDER
13
305
186
338
annual-precip
annual-precip
.14
1
0.54
.01
1
m
HORIZONTAL

PLOT
820
197
1020
347
Grain Supply
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" "ask households [\n  create-temporary-plot-pen (word who)\n  set-plot-pen-color color\n  plotxy ticks grain-supply\n]"
PENS

CHOOSER
18
179
156
224
tenure
tenure
"none" "satisficing" "maximizing"
1

PLOT
817
365
1017
515
Landuse
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"fields" 1.0 0 -955883 true "" "plot (count patches with [field = 1]) * 100 / count patches"
"woodland" 1.0 0 -15575016 true "" "plot (count patches with [vegetation >= 35]) * 100 / count patches"
"maquis" 1.0 0 -12087248 true "" "plot (count patches with [vegetation < 35 and vegetation >= 18]) * 100 / count patches "
"shrub and grassland" 1.0 0 -4399183 true "" "plot (count patches with [vegetation < 18]) * 100 / count patches"
"avg-fertility" 1.0 0 -8431303 true "" "plot mean [fertility] of patches"

SLIDER
15
269
187
302
tenure-drop
tenure-drop
.1
.9
0.2
.1
1
NIL
HORIZONTAL

PLOT
818
36
1018
186
Population
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" "ask households [\n  create-temporary-plot-pen (word who)\n  set-plot-pen-color color\n  plotxy ticks occupants\n]"
PENS

SLIDER
10
141
220
174
wood-req
wood-req
1600
4300
2000.0
10
1
kg/person
HORIZONTAL

SWITCH
24
351
172
384
dynamic-pop
dynamic-pop
1
1
-1000

CHOOSER
15
404
153
449
patches-per-ha
patches-per-ha
0.25 0.5 1 2 4 6 10 16
7

SLIDER
33
493
223
526
expectation-scalar
expectation-scalar
0
1
1.0
.05
1
NIL
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

house two story
false
0
Polygon -7500403 true true 2 180 227 180 152 150 32 150
Rectangle -7500403 true true 270 75 285 255
Rectangle -7500403 true true 75 135 270 255
Rectangle -16777216 true false 124 195 187 256
Rectangle -16777216 true false 210 195 255 240
Rectangle -16777216 true false 90 150 135 180
Rectangle -16777216 true false 210 150 255 180
Line -16777216 false 270 135 270 255
Rectangle -7500403 true true 15 180 75 255
Polygon -7500403 true true 60 135 285 135 240 90 105 90
Line -16777216 false 75 135 75 180
Rectangle -16777216 true false 30 195 93 240
Line -16777216 false 60 135 285 135
Line -16777216 false 255 105 285 135
Line -16777216 false 0 180 75 180
Line -7500403 true 60 195 60 240
Line -7500403 true 154 195 154 255

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.0.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="cell-resolution" repetitions="20" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="200"/>
    <metric>mean [grain-supply] of households</metric>
    <enumeratedValueSet variable="grain-req">
      <value value="212"/>
    </enumeratedValueSet>
    <steppedValueSet variable="expectation-scalar" first="0.7" step="0.05" last="1"/>
    <enumeratedValueSet variable="tenure-drop">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="patches-per-ha">
      <value value="0.25"/>
      <value value="0.5"/>
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
      <value value="6"/>
      <value value="10"/>
      <value value="16"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dynamic-pop">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="init-households">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tenure">
      <value value="&quot;satisficing&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="annual-precip">
      <value value="0.54"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wood-req">
      <value value="2000"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
