extensions [ gis ] ; Load GIS extension for importing environmental layers

breed [ households household ]  ; basic agent type
households-own [
  grain-supply       ; volume of grain held by household
  occupants          ; number of individuals in a household
  babies             ; number of occupants that do not contribute to labor
  fed-prop           ; proportion of a household members receiving enough food

  farm-fields        ; list of patches used by household for farming
  field-max          ; maximum number of farm field patches a household can own, based on number of occupants
  yield-memory        ; average per-patch crop yields in agent memory
  field-yield-estimate ; yield per field estimate
  starve-count
  efficiency-list ; over or undershoot list
  efficiency

  ; not yet fully implemented:
  ; infrastructure
]

breed [ villages village ]       ; collective of households, allows for selective coarse-graining
villages-own [ settled-patches ]   ; list of patches owned by a village but not farmed (i.e. occupied by village)

patches-own [
  vegetation   ; type of vegetation
  fertility    ; soil fertility
  slope-val    ; patch slope, reclassified based on farmability
  patch-yield  ; crop yield of farmed fields

  settlement?   ; does this patch contain a settlement (i.e. village)?
  field?        ; is this patch a farm field?
  owner         ; ID of household owning the patch (if any)

  ;GIS variables not yet fully implemented
  ;cost        ; use LCP map instead of euclidean distances
  ;wetness     ; terrain wetness coefficient
  ;soil-type    ; soil class
]

globals [
  active-patches              ; patches that fall within watershed boundary
  null-patches                ; empty patches that fall beyond watershed boundary
  patches-per-m2              ; how many m2 are in a patch

  annual-precip               ; actual annual precipitation accumulation, in meters
  max-veg                     ; type of climax vegetation
  wood-gather-intensity       ; rate of wood gathering
  max-wood-dist               ; maximum distance household will travel to collect wood

  birth-rate                  ; baseline birth rate for households
  death-rate                  ; baseline death rate for households
  seed-prop                   ; proportion of harvests required for seeds
  starvation-threshold        ; births cease if fed-prop drops below starvation threshold

  max-capita-labor            ; maximum hours of labor available per person in a household
  max-farm-dist               ; maximum distance a household will travel to farm a field
  max-yield                   ; maximum wheat yield given ideal conditions (kg)

  relief-raster               ; GIS raster shaded relief terrain map, for visualization
  soils-raster                ; GIS raster of soil types
  acc-raster                  ; GIS raster of soil wetness (accumulation)
  cost-raster                 ; GIS raster of anisotropic LCPs from village locations
  slope-raster                ; GIS raster of terrain slope, reclassified based on impacts on arability
]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Model setup and initialization                                                                                      ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to setup
  clear-all

  set annual-precip mean-precip     ; initialize precipitation at average value
  set max-veg 50                    ; set climax vegetation to 50 (i.e. uniform mediterranean woodland)
  set wood-gather-intensity 0.08    ; wood gathering rate constant

  set max-capita-labor 250          ; an individual works 250 days out of the year

  set max-farm-dist 200             ; 200 patch farming distance, alternatives -> 75 * sqrt(patches-per-ha) ;1.5 * 60 * 60
  set max-wood-dist 300             ; 300 patch wood gather distance, alternatives -> 150 * sqrt(patches-per-ha) ; 4 * 60 * 60

  set patches-per-m2 patches-per-ha / 10000   ; simple coversion from hectares to m2
  set max-yield 3500 / patches-per-ha         ; convert max yield to mass per unit area
  set seed-prop .15                 ; agents reserve 15% of yields for seed

  set birth-rate 0.054              ; initial birth rate
  set death-rate 0.04               ; initial death rate
  set starvation-threshold 0.6      ; birth ceases if household has less than 60% of its food requirement

  if dev-mode? = False [setup-gis]      ; if diagnostic mode is off, import gis data
  setup-patches                               ; patch-specific setup procedures
  setup-villages                              ; village and household setup procedures
  setup-households

  reset-ticks
end


to setup-gis
  ; load GIS raster maps
  set slope-raster gis:load-dataset "slope.asc"
  set relief-raster gis:load-dataset "relief.asc"

  ; setup simulation world based on input rasters
  set-patch-size 1  ; one patch = one pixel
  gis:set-world-envelope gis:envelope-of slope-raster   ; set boundaries of world to be the same as the input rasters
  resize-world 0 gis:width-of slope-raster 0 gis:height-of slope-raster   ; resize world to match input rasters

  ; set patch-specific variables based on GIS rasters imported earlier
  gis:apply-raster slope-raster slope-val
  gis:paint relief-raster 200  ; use hillshade map to visualize terrain

  ;placeholders for other gis variables not yet fully implemented
  ;set cost-raster gis:load-dataset "cost.asc"
  ;set soils-raster gis:load-dataset "soils.asc"
  ;set acc-raster gis:load-dataset "acc.asc"
  ;gis:apply-raster soils-raster soil-type
  ;gis:apply-raster acc-raster wetness
  ;gis:apply-raster cost-raster cost
end


to setup-patches
  ; check if diagnostic mode is on. if so, setup a world with a uniform environment instead of using GIS data
  if dev-mode? [
    ask patches [ set slope-val 1 ]
    resize-world 0 100 0 100    ; set world size and patch sizes to reasonable values for fast diagnostic runs
    set-patch-size 6
  ]

  ; Now determine which patches are active in the simulation, or should be masked out of computations because they
  ; fall beyond the watershed boundaries of the gis data. calculating these available patches now saves on computational
  ; time during the simulation.
  set active-patches patches with [(slope-val <= 0) or (slope-val >= 0)]  ; necessary workaround to detect all non-null patches in the GIS data
  set null-patches patches != active-patches  ; which patches should be ignored throughout the simulation?

  ; setup routine for patches that will be active during the simulation
  ask active-patches [
    set fertility 100      ; all patches begin with uniform maximum fertility
    set vegetation 50      ; all patches start at climax mediterranean woodland
    set pcolor veg-color   ; change patch color to match vegetation type

    set field? FALSE       ; all patches start out unfarmed
    set owner nobody       ; all pathces start out without an owner
    set settlement? FALSE       ; no patches are settled
    set patch-yield 0      ; yield for unfarmed patches is 0
  ]
end


to setup-villages  ; create villages, then have each village create and initialize households
  create-villages ifelse-value dev-mode? [1] [init-villages] [
    ht  ; hide the village turtles
    ifelse dev-mode?
      [ move-to patch 49 49 ]
    [ move-to one-of active-patches ] ; move villages to random locations

    ; villages create households and initialize them
    hatch-households init-households [
     ; initialize household variables related to food production
      set yield-memory (list [yield "wheat"] of one-of active-patches in-radius 5 with [fertility > 0])  ; give household initial rough estimate of potential crop yields
      set occupants 6                          ; households start off with 6 occupants
      set babies 0                             ; households start off with no babies
      set grain-supply occupants * grain-req   ; households start with enough food to feed its occupants
      set fed-prop 1                           ; ditto
      set farm-fields no-patches               ; households don't own any farm fields
      set starve-count 0
      set efficiency-list []
      ht  ; hide household turtles
    ]

    ; after making households, the village claims patches to use for the physical settlement
    let settled-area max list 1 round(.175 * (sum [occupants] of households-here) ^ .634 * patches-per-ha)  ; settled area scales nonlinearly with population (paramaterizations from Hansen et al 2017)
    set settled-patches min-n-of settled-area active-patches [distance myself]  ; choose patches to settle close to village location
    ask settled-patches [
      set pcolor red
      set owner myself     ; make village owner of patch
      set settlement? TRUE     ; turn patch into settlement
      set vegetation 0     ; clear vegetation from settlement
      set patch-yield 0    ; settled patches don't produce crops
    ]
  ]
end

to setup-households
  ask households [
      ; households figure out how many fields they can farm, and acquire that number or fewer fields
      set field-max floor ((occupants * max-capita-labor) / 40) * patches-per-ha  ; how many patches can a household farm? assuming 40 days of labor required for a field
      choose-farmland min list ((random 10) + 1) field-max                        ; households start with a random number of fields below this maximum
    ]
end
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Runtime                                                                                                             ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to go

  ; if fixed land false, agents can select land every time step. otherwise they only select land at the begining of the simulation
  if fixed-land? = FALSE [
    ask households [
      calculate-field-yield
      check-farmland
    ]

  ; ask households [ allocate-labor ]  ; labor allocation not yet fully implemented
  ]

  if stochastic-rain? [ rain ]         ; generate annual precipitation as a stochastic process
  storage-decay                        ; decay food in storage

  ask households [                     ; each household farms and gathers wood in turn
    farm
  ]

  if dev-mode? = FALSE [ ask households [ gather-wood ] ]

  if dynamic-pop? [birth-death]        ; allow households to grow and die if dynamic-pop? is turned on
  regrow-patch                         ; regenerate vegetation and soil fertility

  tick
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Weather                                                                                                             ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to rain ; generate rainfall as a stochastic process, approximately gaussian, with optional AR(1) persistence
  set annual-precip max list 0 ( ( mean-precip + (annual-precip - mean-precip) * persistence ) * ( 1 + precip-CV * random-normal 0 1 ) )
end

to storage-decay
  ask households [ set grain-supply grain-supply - grain-supply * .3 ]
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Land selection and tenure                                                                                           ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; dynamic labor allocation not yet fully implemented
;to allocate-labor
  ;let profit yield-memory * man-hours ^ 0.3 * (infrastructure + annual-rainfall) ^ 0.4 * (count farm-fields * patches-per-ha) ^ 0.3
;end

to calculate-field-yield ; household calculates the field number needed from the yield-memory and the field-decision-strat
  if field-decision-strat = "last year" [
    set field-yield-estimate (last yield-memory)
  ]
  if field-decision-strat = "average" [
    set field-yield-estimate (mean yield-memory)
  ]
  if field-decision-strat = "lowest" [
    set field-yield-estimate (min yield-memory)
  ]
  if field-decision-strat = "random-uniform" [  ; add something like normal distribution later?
    set field-yield-estimate (one-of yield-memory)
  ]
  if field-decision-strat = "avg(lowest+last)" [
    set field-yield-estimate (mean list (min yield-memory) (last yield-memory))
  ]
  ; if field-decision-strat = "gambler's fallacy" [ ; to be implemented
  ;  set field-yield-estimate ( ) ]

end


to check-farmland ; agents assess how many fields they need given household size, crop yields, and tenure strategy, and add or drop land accordingly
  ; calcuates fields required
  let field-req 0
  carefully [
    set field-req  round ((occupants * grain-req * (1 + seed-prop)) / (field-yield-estimate * expectation-scalar))
  ][
    set field-req field-max
  ]
  set field-req (min list field-req field-max)
  ifelse tenure = "none" [   ; if no land tenure, household drops all fields and chooses new ones
    if count farm-fields > 0 [ drop-farmland (count farm-fields) ]
    choose-farmland (field-req)
  ][
    if field-req < count farm-fields [ drop-farmland (count farm-fields - field-req) ]   ; drop unneeded fields
    if field-req > count farm-fields and any? other active-patches with [fertility > 0 and owner = nobody]  ; acquire more fields if needed
      [ choose-farmland (field-req - count farm-fields) ]
  ]
end


to drop-farmland [num-fields]  ; routine that drops a given number of fields according to a land tenure strategy
 let mean-yield mean [patch-yield] of farm-fields     ; calculate average yield of all fields a household owns, to detect underperforming plots
 let max-patch-yield max [patch-yield] of farm-fields ; calculate best performing field a household owns

 let drop-fields ifelse-value (tenure = "maximizing") ; calculate a list of fields to drop
    [ farm-fields with [ patch-yield < (max-patch-yield * (1 - tenure-drop)) ] ]  ; if tenure strategy is maximizing, drop the lowest performing tenure-drop proportion of fields
    [ n-of num-fields farm-fields ]  ; otherwise just drop the fields that need to be dropped

  ask drop-fields [       ; routine for resotring dropped farm fields to their "natural" state
    set owner nobody      ; unfarmed fields have no owner
    set patch-yield 0     ; unfarmed fields have no crop yields
    set field? FALSE     ; no longer a field
    set pcolor veg-color  ; update patch color to vegetation
  ]

  set farm-fields farm-fields with [owner = myself]  ; update the household's list of fields it owns
end




to choose-farmland [num-fields]   ; routine for a household to evaluate nearby patches and select new farm fields
  ; choose num-fields patches that are unowned and nearby, sorted by farm-val
  let new-fields max-n-of num-fields active-patches in-radius 50 with [owner = nobody] [farm-val]

  ask new-fields [
    set owner myself   ; take ownership of patch
    set field? TRUE    ; turn into a field
    set vegetation 5   ; clear vegetation to grass
  ]

  set farm-fields (patch-set farm-fields new-fields)  ; add new fields to existing farm fields
end


to-report farm-val  ; decision algorithm to assign value to patches with low slopes, high fertility, and less vegetation that are closer to the village
  let lcdeval (ifelse-value (vegetation <= 30) [ vegetation * 25 / 30 ] [ vegetation * 65 / 20 - 72.5 ]) / 100  ; agents prefer certain vegetation types
  let frag-val 1 - (count neighbors with [owner = myself]) / 8     ; agents prefer continuous fields to fragmented one

  report slope-val * (fertility / 100 - (distance myself / max-farm-dist + lcdeval + frag-val) / 3)
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Farming and harvesting                                                                                              ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to farm ; agents harvest food from patch and feed occupants
  ; calculate yields from each farmed patch and modify patch accordingly
  ask farm-fields [
    ifelse fertility > 0                                 ; only farm fertile patches
      [ set patch-yield yield "wheat"                    ; calculate yields
        set fertility (fertility - random-normal 3 2) ]  ; reduce fertility of farmed patch
      [ set patch-yield 0 ]                              ; no yields if not fertile
    if fertility < 0 [ set fertility 0 ]                   ; fertility can't be negative
    set pcolor 39 - (8 * fertility / 100)                ; adjust patch color to reflect soil fertility
   ]

  ; harvest grain, store it, and feed the household
  let total-harvest sum [patch-yield] of farm-fields                             ; combine yields from all farmed patches
  if ticks > 25 [
    set efficiency-list lput abs (total-harvest - (grain-req * occupants * (1 + seed-prop))) efficiency-list
    set efficiency mean efficiency-list
    if total-harvest < (grain-req * occupants * (1 + seed-prop)) [
      set starve-count starve-count + 1
    ]
  ]
  set grain-supply grain-supply + total-harvest * (1 - seed-prop)                ; store what's left after removing some grain for seed
  set fed-prop grain-supply / (grain-req * occupants)                   ; what proportion of household is able to be fed?
  set grain-supply max list 0 (grain-supply - grain-req * occupants)  ; subtract consumed food from storage without going negative

  remember

end

to remember
  ; store yield info in agent memory
  let mean-yield mean [ patch-yield ] of farm-fields                ; calculate average patch crop yield
  set yield-memory lput mean-yield yield-memory
  if (length yield-memory) > yield-memory-length                    ; comparing memory length to slider memory length input
  	[ set yield-memory remove-item 0 yield-memory ]
  ;set fuzzy-yield-memory random-normal mean-yield (mean-yield * .0333)     ; store averge crop yield in memory, with some error;
end



to-report yield [crop]  ; report crop yields given yield-reduction factors based on nonlinear multiple regression of ethnographic data (see MedLands project)
  ifelse annual-precip >= .14  ; if there is rain, get yields. must have at least .14 meters for any yields
    [ let potential-yield ifelse-value (crop = "wheat")
        [ (((0.51 * ln(annual-precip)) + 1.03) * ((0.19 * ln(fertility / 100)) + 1)) / 2 ]    ; wheat potential yields
        [ (((0.48 * ln(annual-precip)) + 1.51) * ((0.18 * ln(fertility / 100)) + .98)) / 2 ]  ; barley potential yields
      report (potential-yield * slope-val * max-yield) / patches-per-ha ]   ; modify yields based on slope and make areal unit conversion
    [ report 0 ] ; no yields if no rain
end




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Wood gathering                                                                                                      ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to gather-wood  ; harvest firewood from vegetated patches
  let num-patches round(occupants * wood-req / (wood-gather-intensity / patches-per-m2))  ; determine the number of patches a houshold needs to get wood from

  ; select wood gathering patches based on distance and vegetation type
  let wood-patches max-n-of (min list num-patches count (active-patches with [vegetation >= 9] in-radius 90)) (active-patches with [vegetation >= 9] in-radius 90) [ ((vegetation - 9) / 41 + (3 * (1 - (distance myself / max-wood-dist)))) / (1 + 3) ]
  ask wood-patches [   ; patches with different amounts of vegetation have different amounts of woody biomass available
      ifelse vegetation > 35
      [ set vegetation ((vegetation * .0806 - 2.08) - wood-gather-intensity + 2.08) / .0806 ]
      [ ifelse vegetation > 18
        [ set vegetation ((vegetation * .0047 + .5755) - wood-gather-intensity - .5755) / .0047 ]
        [ set vegetation ((vegetation * .0509 - .2562) - wood-gather-intensity + .2562) / .0509 ]]
      if vegetation < 0 [ set vegetation 0 ]
  ]
end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Demography                                                                                                          ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to birth-death   ; add or remove occupants from household, based on fed proportion of household
  ask households [
    if ticks mod 15 = 0 [ set babies 0 ]        ; babies turn to laborers every 15 years
    let deaths (random-poisson (death-rate * 100)) / 100 * occupants  ; death rate determined by poisson process
    let births ifelse-value (fed-prop >= starvation-threshold)        ; births only occur if there is enough food, otherwise nothing happens
      [ (random-poisson (birth-rate * 100)) / 100 * occupants ]
      [ 0 ]
    if (births - deaths != 0) [                  ; check to see if household size has changed
      set occupants occupants + births - deaths  ; adjust household size
      if occupants <= 0 [ die ]                  ; die if no one's left
      set babies babies + births                 ; increase babies if any births occurred
      set field-max floor (((occupants - babies) * max-capita-labor) / 40) * patches-per-ha   ; adjust a household's max fields based on available labor
    ]
  ]

  ; check to see if villages needs to grow
  ask villages [
    let settled-area max list 1 round(.175 * (sum [occupants] of households-here) ^ .634 * patches-per-ha) ; population to settled area determined by power law relationship
    if settled-area != count settled-patches [ adjust-settlement-size (settled-area - count settled-patches) ]  ; if there are too many people, grow the village
  ]
end


to adjust-settlement-size [patch-diff]  ; change settled area to reflect new village population
  ifelse patch-diff > 0            ; need to add or subtract settled patches?
    [ repeat patch-diff [          ; for each patch to be added ...
        ask one-of active-patches in-radius 3 with [any? neighbors4 with [settlement? = TRUE]][  ; select neighboring empty patch
          set owner myself           ; take control of patch
          set pcolor red             ; change color to village
          set settlement? TRUE       ; mark as settled
          set field? FALSE           ; remove any fields
          set vegetation 0           ; remove vegetation
          set patch-yield 0
        ]
      ]
    ][
      ask max-n-of abs(patch-diff) settled-patches [distance myself] [  ; for each patch to be removed ...
        set owner nobody     ; reset ownership
        set settlement? FALSE     ; remove settlement
        set pcolor veg-color ; reset vegetation color
      ]
    ]

  set settled-patches active-patches with [owner = myself] ; update village's list of patches it owns
end


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Vegetation dynamics                                                                                                 ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to regrow-patch ; restore patch vegetation and soil fertility
  ask active-patches [

    if fertility < 100 [ set fertility fertility + random-normal 2 .5 ] ; restore fertility by restoration rate, with some noise
    if fertility > 100 [ set fertility 100 ]                            ; fertility can't excede 100

    ;restore vegetation on unfarmed, unsettled patches
    if field? = FALSE and settlement? = FALSE [
      if vegetation < max-veg [
        ; determine vegetation regrowth rate based on soil factors and regrow accordingly
        let regrowth-rate ((-0.000118528 * fertility ^ 2) + (0.0215056 * fertility) + 0.0237987)
        set vegetation vegetation + regrowth-rate

        if vegetation > max-veg [ set vegetation max-veg ]  ; can't excede climax vegetation
        set pcolor veg-color
      ]
    ]
  ]
end

to-report veg-color ; quickly calculate patch color based on vegetation
  report 59.9 - (vegetation * 7.9 / 50)
end
@#$#@#$#@
GRAPHICS-WINDOW
286
10
900
625
-1
-1
6.0
1
10
1
1
1
0
0
0
1
0
100
0
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
149
12
213
45
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
9
132
181
165
init-households
init-households
0
50
5.0
1
1
NIL
HORIZONTAL

SLIDER
14
606
214
639
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
10
463
177
496
mean-precip
mean-precip
.14
1
0.9
.01
1
m
HORIZONTAL

PLOT
707
627
907
777
Grain Supply
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
"pen-0" 1.0 0 -3844592 true "" "plot mean [grain-supply] of households"

CHOOSER
7
238
145
283
tenure
tenure
"none" "satisficing" "maximizing"
1

PLOT
928
625
1128
775
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
"fields" 1.0 0 -955883 true "" "plot (count patches with [field? = TRUE]) * 100 / count patches"
"woodland" 1.0 0 -15575016 true "" "plot (count patches with [vegetation >= 35]) * 100 / count patches"
"maquis" 1.0 0 -12087248 true "" "plot (count patches with [vegetation < 35 and vegetation >= 18]) * 100 / count patches "
"shrub and grassland" 1.0 0 -4399183 true "" "plot (count patches with [vegetation < 18]) * 100 / count patches"

SLIDER
8
289
180
322
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
498
624
698
774
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
15
642
225
675
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
129
686
284
719
dynamic-pop?
dynamic-pop?
1
1
-1000

CHOOSER
17
680
127
725
patches-per-ha
patches-per-ha
0.25 0.5 1 1.25 2 4 6 10 16
3

SLIDER
8
329
198
362
expectation-scalar
expectation-scalar
0
1
1.0
.05
1
NIL
HORIZONTAL

PLOT
1133
626
1333
776
fertility
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
"default" 1.0 0 -16777216 true "" "plot mean [fertility] of patches with [owner != nobody]"

SLIDER
8
169
180
202
init-villages
init-villages
0
30
0.0
1
1
NIL
HORIZONTAL

SWITCH
10
95
187
128
dev-mode?
dev-mode?
0
1
-1000

TEXTBOX
10
69
160
87
Basic setup
12
0.0
1

TEXTBOX
24
216
174
234
Land tenure
12
0.0
1

TEXTBOX
17
586
167
604
Constants
12
0.0
1

SWITCH
11
367
144
400
fixed-land?
fixed-land?
1
1
-1000

PLOT
282
626
482
776
Precipitation
NIL
NIL
0.0
10.0
0.0
1.5
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot annual-precip"

TEXTBOX
11
412
161
430
Weather
12
0.0
1

SLIDER
10
498
182
531
precip-CV
precip-CV
0
.9
0.8
.1
1
NIL
HORIZONTAL

SWITCH
10
428
181
461
stochastic-rain?
stochastic-rain?
0
1
-1000

SLIDER
9
533
181
566
persistence
persistence
0
1
0.9
.1
1
NIL
HORIZONTAL

SLIDER
928
29
1100
62
yield-memory-length
yield-memory-length
1
50
45.0
1
1
NIL
HORIZONTAL

PLOT
929
462
1129
612
Fed Proportion
NIL
NIL
0.0
10.0
0.0
2.0
true
false
"" "ask households [\n  create-temporary-plot-pen (word who)\n  set-plot-pen-color color\n  plotxy ticks fed-prop\n]"
PENS

CHOOSER
932
96
1075
141
field-decision-strat
field-decision-strat
"random-uniform" "last year" "lowest" "average" "avg(lowest+last)"
2

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
NetLogo 6.0.2
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
  <experiment name="strategy-experiment" repetitions="100" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="125"/>
    <metric>mean [starve-count] of households</metric>
    <metric>mean [efficiency] of households</metric>
    <enumeratedValueSet variable="field-decision-strat">
      <value value="&quot;avg(lowest+last)&quot;"/>
      <value value="&quot;average&quot;"/>
      <value value="&quot;lowest&quot;"/>
      <value value="&quot;random-uniform&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="grain-req">
      <value value="212"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stochastic-rain?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="patches-per-ha">
      <value value="1.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-land?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dynamic-pop?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="init-households">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="precip-CV">
      <value value="0.2"/>
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="yield-memory-length">
      <value value="1"/>
      <value value="5"/>
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="init-villages">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dev-mode?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="expectation-scalar">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tenure-drop">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mean-precip">
      <value value="0.3"/>
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tenure">
      <value value="&quot;satisficing&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="persistence">
      <value value="0.5"/>
      <value value="0"/>
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wood-req">
      <value value="2000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="memory-experiment" repetitions="50" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="125"/>
    <metric>mean [starve-count] of households</metric>
    <metric>mean [efficiency] of households</metric>
    <enumeratedValueSet variable="field-decision-strat">
      <value value="&quot;avg(lowest+last)&quot;"/>
      <value value="&quot;average&quot;"/>
      <value value="&quot;lowest&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="grain-req">
      <value value="212"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stochastic-rain?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="patches-per-ha">
      <value value="1.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-land?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dynamic-pop?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="init-households">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="precip-CV">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="yield-memory-length">
      <value value="1"/>
      <value value="5"/>
      <value value="15"/>
      <value value="25"/>
      <value value="35"/>
      <value value="45"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="init-villages">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dev-mode?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="expectation-scalar">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tenure-drop">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mean-precip">
      <value value="0.3"/>
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tenure">
      <value value="&quot;satisficing&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="persistence">
      <value value="0.5"/>
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="wood-req">
      <value value="2000"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="memory-experiment2" repetitions="50" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="125"/>
    <metric>mean [starve-count] of households</metric>
    <enumeratedValueSet variable="field-decision-strat">
      <value value="&quot;avg(lowest+last)&quot;"/>
      <value value="&quot;average&quot;"/>
      <value value="&quot;lowest&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="grain-req">
      <value value="212"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stochastic-rain?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="patches-per-ha">
      <value value="1.25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="fixed-land?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dynamic-pop?">
      <value value="false"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="init-households">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="precip-CV">
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="yield-memory-length">
      <value value="1"/>
      <value value="5"/>
      <value value="15"/>
      <value value="25"/>
      <value value="35"/>
      <value value="45"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="init-villages">
      <value value="0"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="dev-mode?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="expectation-scalar">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tenure-drop">
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="mean-precip">
      <value value="0.3"/>
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="tenure">
      <value value="&quot;satisficing&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="persistence">
      <value value="0.9"/>
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
