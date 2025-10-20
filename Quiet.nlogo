extensions [csv fetch]
;; The fetch extension allows importing CSV files from URLs or local file inputs
;; CSV extension provides robust parsing, fetch extension enables file-based imports

globals [
  class-x class-y        ;; patch coords of box's upper right corner
  teacher-x teacher-y    ;; patch coords of teacher
  noise-history
  total-noise
  counter ; counts zero noise that were counted as one in the list of noise
  blue-spontaneous-bother-probability ;; for optimization
  blue-contagion-bother-probability
  blue-teacher-proximity-bother-probability

  panel-alpha-sort?   ;; if true, alphabetize within each color group
  
  light-blue-spontaneous-bother-probability
  light-blue-contagion-bother-probability
  light-blue-teacher-proximity-bother-probability
	
  panel-line-y
  
  white-spontaneous-bother-probability
  white-contagion-bother-probability
  white-teacher-proximity-bother-probability

  radius-of-influence

  ;; Mouse interaction state variables for NetLogo Web
  selected-turtle
  mouse-was-down?
  
  ;; Student panel variables
  student-data        ;; list of student information from CSV
  panel-student-list  ;; students displayed in the panel
  panel-x panel-y     ;; position of the student panel
  selected-from-panel ;; student selected from panel for dragging
  ;
  ;one-over-probability

  
  
  
  seats-list          ;; [(x y) ...] current student seat coords (y > -22)
  seats-sens-list     ;; [ [(x y) sens] ... ] lower = safer, sorted ASC
  rng-seeds           ;; CRN seeds per repeat
  alpha-dist          ;; seat sensitivity weight for distance
  beta-neigh          ;; seat sensitivity weight for neighbor density
  
  bf-partial
  bf-best-score
  bf-best-assign
  bf-R
  bf-nTicks
  bf-M
  
  opt-fast?          ;; when true, evaluations run with no plotting/list growth
  opt-sum-noise      ;; running sum of noise during a headless evaluation
  opt-step-count     ;; ticks counted during a headless evaluation
  plot-max-points    ;; keep only the most recent N points for the UI plot

  opt-last-method
  opt-last-score
  opt-last-time
  opt-last-note

  ;; ---- Branch & Bound (types) globals ----
  bnb-partial
  bnb-best-score
  bnb-best-assign
  bnb-R
  bnb-nTicks
  bnb-M
  bnb-visited
  bnb-pruned
  bnb-best-proxy
  bnb-seat-sens
  bnb-seats
  bnb-max-nodes
  bnb-deadline
  bnb-admissible?    ;; true = safe LB (0), false = calibrated heuristic LB
  bnb-calib-a bnb-calib-b bnb-calib-margin
  bnb-seat-lb-D  
  bnb-seat-lb-T  
  bnb-seat-lb-Q  ;; per-seat lower-bound deltas for D/T/Q
	bnb-d0 bnb-t0
	bnb-lb-dp
	bnb-prefix-best
  bnb-start-time       ;; time anchor for the whole run
  bnb-timeout-hit?     ;; print "Hit time budget" only once

]
breed [teachers teacher]

breed [tables table]

breed [students student]

breed [panel-students panel-student]  ;; students in the panel


turtles-own [probability-bother  close-window? close-door? close-teacher? bothering? student-name student-type]

students-own [distance-from-teacher bothering-in-radius spontaneous-bother-probability  contagion-bother-probability
                teacher-proximity-bother-probability                   bother?
								risk]
panel-students-own []
;; inherits student-name and student-type from turtles-own



to reset
set noise-history []
clear-all-plots
ask students [ set size 1 set bother? 0 ]
set-probabilities
ask students [ set-probabilities-by-color ]
reset-ticks
end

to setup
  ca
  ;; Clear any old static panel elements
  clear-old-static-panel
	set opt-fast? false
	set plot-max-points 500   ;; keep plot compact
  set bnb-admissible? true

  ;; Initialize mouse state variables
  set selected-turtle nobody
  set mouse-was-down? false
  set selected-from-panel nobody
  set panel-alpha-sort? true
  ;; Initialize panel variables (positioned at bottom right)
  set panel-x 15
  set panel-y -25
  set panel-line-y -22
  set student-data []

  ask patches [if pycor = -22 [set pcolor white]]
  set noise-history [  ]
  set-probabilities
  ask students [ set-probabilities-by-color ]

  ;; Start with empty panel - users must load their own data
  print "Classroom setup complete. Use 'Load CSV Data'to add students."

  reset-ticks
end

to set-probabilities-by-color
  if color = blue [ set spontaneous-bother-probability blue-spontaneous-bother-probability
                  set contagion-bother-probability blue-contagion-bother-probability
                  set teacher-proximity-bother-probability blue-teacher-proximity-bother-probability ]

  if color = 107 [ set spontaneous-bother-probability  light-blue-spontaneous-bother-probability
                  set contagion-bother-probability  light-blue-contagion-bother-probability
                  set teacher-proximity-bother-probability light-blue-teacher-proximity-bother-probability ]

  if color = white [ set spontaneous-bother-probability  white-spontaneous-bother-probability
                  set contagion-bother-probability white-contagion-bother-probability                     set teacher-proximity-bother-probability white-teacher-proximity-bother-probability  ]
end



to set-probabilities
set blue-spontaneous-bother-probability 70
set blue-contagion-bother-probability 60
set blue-teacher-proximity-bother-probability 20

set light-blue-spontaneous-bother-probability 50
set light-blue-contagion-bother-probability 50
set light-blue-teacher-proximity-bother-probability 50

set white-spontaneous-bother-probability 10
set white-contagion-bother-probability  30
set white-teacher-proximity-bother-probability 80

set radius-of-influence 6
  
  
  
; set radius-of-influence 6

; ; Disruptive
; set blue-spontaneous-bother-probability 70
; set blue-contagion-bother-probability 60
; set blue-teacher-proximity-bother-probability 80

; ; Talkative
; set light-blue-spontaneous-bother-probability 50
; set light-blue-contagion-bother-probability 45
; set light-blue-teacher-proximity-bother-probability 55

; ; Quiet
; set white-spontaneous-bother-probability 12
; set white-contagion-bother-probability 20
; set white-teacher-proximity-bother-probability 20
  

end


to go
  every 1 [
    go-once
  ]
end

to go-once
  if any? teachers with [ycor > -22] [
    let teacher-identity one-of teachers with [ycor > -22]
    set teacher-x [xcor] of teacher-identity
    set teacher-y [ycor] of teacher-identity

    ask students with [ycor > -22] [
      set distance-from-teacher distancexy teacher-x teacher-y

      ifelse (any? students in-radius radius-of-influence
                    with [size = 3] and who != [who] of self) [
        set bothering-in-radius 1
      ] [
        set bothering-in-radius 0
      ]

      ifelse random 100 <
        (spontaneous-bother-probability
         + contagion-bother-probability * bothering-in-radius
         - teacher-proximity-bother-probability
           / (max (list distance-from-teacher 0.1))) [
        set bother? 1
        set size 3
      ] [
        set bother? 0
        set size 1
      ]
    ]
  ]
  
  ;;compute current noise count
  let noise-now count students with [ycor > -22 and size = 3]

  ifelse opt-fast? [
    ;;FAST EVALUATION no plotting, no long lists
    set opt-sum-noise  opt-sum-noise  + noise-now
    set opt-step-count opt-step-count + 1
    set total-noise (opt-sum-noise / (max (list 1 opt-step-count)))
  ] [
    ;; NORMAL UI MODE: update short history for plotting
    ifelse (noise-now > 0) [
      set noise-history fput (1 + noise-now) noise-history
    ] [
      set noise-history fput 1 noise-history
    ]
    ;; keep only the most recent plot-max-points items
    if (length noise-history > plot-max-points) [
      set noise-history sublist noise-history 0 plot-max-points
    ]
    set total-noise (mean noise-history - 1)
  ]

	if not opt-fast? [ tick ]

end


;create classroom
;; allows the user to place the box by clicking on one corner.
to place-class
  if mouse-inside? and mouse-xcor > -11 [
    set class-x max (list 2 (abs round mouse-xcor))
    set class-y max (list 2 (abs round mouse-ycor))
    draw-class
    ask patch 0 20 [set plabel (precision ((2 * class-x + 1) / 5) 0) set plabel-color yellow]
    ask patch 20 0 [set plabel (precision ((2 * class-y + 1) / 5) 0) set plabel-color yellow]
    display
  ]
  if mouse-down? [ stop ]
end

to draw-class
  ask patches [ 
    if (pycor > -21) [
      set pcolor ifelse-value is-class? class-x class-y [ yellow ] [ black ]
    ]
  ]
end

to-report is-class? [ x y ] ;; patch reporter
  report (abs pxcor = x and abs pycor <= y) or (abs pycor = y and abs pxcor <= x)
end


;; FOREVER BUTTON: Drag and drop system for NetLogo Web
to drag-turtles
  ;; pick up any turtle (including panel-students)
  if mouse-down? and not mouse-was-down? [
    set selected-turtle min-one-of turtles [ distancexy mouse-xcor mouse-ycor ]
    if selected-turtle != nobody and
       [ distancexy mouse-xcor mouse-ycor ] of selected-turtle > 2 [
      set selected-turtle nobody
    ]
  ]

  ;; while holding, move it
  if mouse-down? and selected-turtle != nobody [
    ask selected-turtle [
      setxy mouse-xcor mouse-ycor
    ]
  ]

  ;; on release, if it was a panel-student convert it, otherwise leave it
  if not mouse-down? and selected-turtle != nobody [
    ;; if it was a panel-student, convert it
    if ([breed] of selected-turtle) = panel-students [
      ;; tell the panel-dropper exactly which one it is:
      set selected-from-panel selected-turtle

      ;; now place it at its current position:
      place-student-from-panel 
        ([xcor] of selected-from-panel) 
        ([ycor] of selected-from-panel)

      ;; kill the panel icon
      ask selected-from-panel [ die ]

      ;; clear that helper var
      set selected-from-panel nobody
    ]
    ;; otherwise leave a regular turtle where it was dropped
    set selected-turtle nobody
  ]

  set mouse-was-down? mouse-down?
end


to move-students
  if mouse-down? and not mouse-was-down? [
    let closest-student min-one-of students [distancexy mouse-xcor mouse-ycor]
    if closest-student != nobody and [distancexy mouse-xcor mouse-ycor] of closest-student <= 2 [
      ask closest-student [
        setxy mouse-xcor mouse-ycor
      ]
    ]
  ]
  set mouse-was-down? mouse-down?
end



to drag-from-panel
  ;; Mouse pressed for the first time - pick up a panel student
  if mouse-down? and not mouse-was-down? [
    let closest-panel min-one-of panel-students [distancexy mouse-xcor mouse-ycor]
    if closest-panel != nobody and [distancexy mouse-xcor mouse-ycor] of closest-panel <= 2 [
      set selected-from-panel closest-panel
      print (word "Picked up " [student-name] of closest-panel)
    ]
  ]

  ;; While holding the mouse, move the selected turtle with it
  if mouse-down? and selected-from-panel != nobody [
    ask selected-from-panel [
      set size 2.5
      set label-color red
      setxy mouse-xcor mouse-ycor          ;;this moves the turtle!
    ]
  ]

  ;; when release the mouse, drop the student into the classroom
  if not mouse-down? and selected-from-panel != nobody [
    ;; only place if over the valid classroom area
    ifelse (mouse-ycor > -21) [
      place-student-from-panel mouse-xcor mouse-ycor
    ] [
      print "Please release the student in the classroom (above the white line)."
    ]

    ;; restore the panel-student’s appearance
    ask selected-from-panel [
      set size 1.5
      set label-color black
    ]
    set selected-from-panel nobody
  ]

  ;; remember the previous mouse state
  set mouse-was-down? mouse-down?
end



to place-student-from-panel [x y]
  if selected-from-panel != nobody [
    let name-to-place [student-name] of selected-from-panel
    let type-to-place [student-type] of selected-from-panel
    
    ;; Create actual student in classroom
    ask patch (round x) (round y) [
      ifelse not any? turtles-here with [
               breed = students or
               breed = teachers or
               breed = tables
             ]
      [
        sprout-students 1 [
          set student-name name-to-place
          set student-type type-to-place
          set shape "circle"
          set size 1
          
          ;; Set color and properties based on type
          if type-to-place = "disruptive" [
            set color blue
            set spontaneous-bother-probability blue-spontaneous-bother-probability
            set contagion-bother-probability blue-contagion-bother-probability
            set teacher-proximity-bother-probability blue-teacher-proximity-bother-probability
          ]
          if type-to-place = "talkative" [
            set color 107
            set spontaneous-bother-probability light-blue-spontaneous-bother-probability
            set contagion-bother-probability light-blue-contagion-bother-probability
            set teacher-proximity-bother-probability light-blue-teacher-proximity-bother-probability
          ]
          if type-to-place = "quiet" [
            set color white
            set spontaneous-bother-probability white-spontaneous-bother-probability
            set contagion-bother-probability white-contagion-bother-probability
            set teacher-proximity-bother-probability white-teacher-proximity-bother-probability
          ]
          
          set label name-to-place
          set label-color red
        ]
        
        print (word "Placed " name-to-place " (" type-to-place ") in classroom at (" 
                     round x ", " round y ")")
      ]
      [
        print (word "Cannot place " name-to-place " - position occupied")
      ]
    ]
  ]
end


;; Toggle student name labels on/off
to toggle-student-names
  ask students [
    ifelse label = "" [
      set label student-name
      set label-color red
    ] [
      set label ""
    ]
  ]
  print "Student name labels toggled"
end

;; Return student-data grouped by type: disruptive -> talkative -> quiet
;;in order to sort panel
to-report sort-student-data [data]
  let dis   filter [ row -> item 1 row = "disruptive" ] data
  let talk  filter [ row -> item 1 row = "talkative"  ] data
  let quiet filter [ row -> item 1 row = "quiet"      ] data

  if panel-alpha-sort? [
    set dis   sort-student-subgroup dis
    set talk  sort-student-subgroup talk
    set quiet sort-student-subgroup quiet
  ]

  report sentence dis (sentence talk quiet)
end


;; Alphabetize a subgroup by student name (item 0)
to-report sort-student-subgroup [lst]
  report sort-by [[a b] -> (item 0 a) < (item 0 b)] lst
end

;; Add students directly by clicking
to add-noisy-students
  if mouse-down? and not mouse-was-down? [
    ask patch mouse-xcor mouse-ycor [
      if not any? turtles-here [
        sprout-students 1 [ 
          set shape "circle" 
          set size 1 
          set color blue
          set student-name "Student"
          set student-type "disruptive"
          set spontaneous-bother-probability blue-spontaneous-bother-probability
          set contagion-bother-probability blue-contagion-bother-probability
          set teacher-proximity-bother-probability blue-teacher-proximity-bother-probability
        ]
      ]
    ]
  ]
  set mouse-was-down? mouse-down?
end

to add-talkative-students
  if mouse-down? and not mouse-was-down? [
    ask patch mouse-xcor mouse-ycor [
      if not any? turtles-here [
        sprout-students 1 [ 
          set shape "circle" 
          set size 1 
          set color 107
          set student-name "Student"
          set student-type "talkative"
          set spontaneous-bother-probability light-blue-spontaneous-bother-probability
          set contagion-bother-probability light-blue-contagion-bother-probability
          set teacher-proximity-bother-probability light-blue-teacher-proximity-bother-probability
        ]
      ]
    ]
  ]
  set mouse-was-down? mouse-down?
end

to add-quiet-students
  if mouse-down? and not mouse-was-down? [
    ask patch mouse-xcor mouse-ycor [
      if not any? turtles-here [
        sprout-students 1 [ 
          set shape "circle" 
          set size 1 
          set color white
          set student-name "Student"
          set student-type "quiet"
          set spontaneous-bother-probability white-spontaneous-bother-probability
          set contagion-bother-probability white-contagion-bother-probability
          set teacher-proximity-bother-probability white-teacher-proximity-bother-probability
        ]
      ]
    ]
  ]
  set mouse-was-down? mouse-down?
end

to add-teacher
  if mouse-down? and not mouse-was-down? [
    set teacher-x round mouse-xcor
    set teacher-y round mouse-ycor
    ask patch teacher-x teacher-y [ 
      sprout-teachers 1 [
        set shape "teacher-table-1"  
        set size 6
      ]
    ]
  ]
  set mouse-was-down? mouse-down?
end

to add-teacher-2
  if mouse-down? and not mouse-was-down? [
    set teacher-x round mouse-xcor
    set teacher-y round mouse-ycor
    ask patch teacher-x teacher-y [ 
      sprout-teachers 1 [
        set shape "teacher-table-2"  
        set size 6
      ]
    ]
  ]
  set mouse-was-down? mouse-down?
end

to remove-teacher
  if mouse-down? and not mouse-was-down? [
    ask patch mouse-xcor mouse-ycor [ 
      if any? teachers-here [
        ask teachers-here [die]
      ]
    ]
  ]
  set mouse-was-down? mouse-down?
end

to add-horizontal-table
  if mouse-down? and not mouse-was-down? [
    ask patch mouse-xcor mouse-ycor [
      sprout-tables 1 [ 
        set shape "table-horizontal" 
        set size 4
      ]
    ]
  ]
  set mouse-was-down? mouse-down?
end

to add-vertical-table
  if mouse-down? and not mouse-was-down? [
    ask patch mouse-xcor mouse-ycor [
      sprout-tables 1 [ 
        set shape "table-vertical" 
        set size 4
      ]
    ]
  ]
  set mouse-was-down? mouse-down?
end

to remove-thing
  if mouse-down? and not mouse-was-down? [
    ask patch mouse-xcor mouse-ycor [ 
      if any? turtles-here [
        ask turtles-here [die]
      ]
    ]
  ]
  set mouse-was-down? mouse-down?
end


;; Split a string by a delimiter
to-report split-string [str delimiter]
    let result []
    let current-word ""
    let i 0
    
    while [i < length str] [
        let char substring str i (i + 1)
        ifelse char = delimiter [
        if current-word != "" [
            set result lput current-word result
            set current-word ""
        ]
        ] [
        set current-word (word current-word char)
        ]
        set i i + 1
    ]
    
    ;; Add the last word if there is one
    if current-word != "" [
        set result lput current-word result
    ]
  
  report result
end

;; Convert string to lowercase
to-report string-downcase [str]
    let result ""
    let i 0
    while [i < length str] [
        let char substring str i (i + 1)
        ;; Simple lowercase conversion for common letters
        if char = "A" [ set char "a" ]
        if char = "B" [ set char "b" ]
        if char = "C" [ set char "c" ]
        if char = "D" [ set char "d" ]
        if char = "E" [ set char "e" ]
        if char = "F" [ set char "f" ]
        if char = "G" [ set char "g" ]
        if char = "H" [ set char "h" ]
        if char = "I" [ set char "i" ]
        if char = "J" [ set char "j" ]
        if char = "K" [ set char "k" ]
        if char = "L" [ set char "l" ]
        if char = "M" [ set char "m" ]
        if char = "N" [ set char "n" ]
        if char = "O" [ set char "o" ]
        if char = "P" [ set char "p" ]
        if char = "Q" [ set char "q" ]
        if char = "R" [ set char "r" ]
        if char = "S" [ set char "s" ]
        if char = "T" [ set char "t" ]
        if char = "U" [ set char "u" ]
        if char = "V" [ set char "v" ]
        if char = "W" [ set char "w" ]
        if char = "X" [ set char "x" ]
        if char = "Y" [ set char "y" ]
        if char = "Z" [ set char "z" ]
        
        set result (word result char)
        set i i + 1
  ]
  report result
end


;; Clear all student data and reset the panel
to clear-student-data
  set student-data []
  ask panel-students [ die ]
  ask students [ die ]
  ask patches with [plabel = "STUDENT PANEL"] [ set plabel "" ]
  print "All student data cleared."
end

;; =================================================================
;; CSV IMPORT

;; Main file-based CSV import - supports both file upload and URL import
to load-student-csv-from-file
    print "File-based CSV Import Options:"
    print "1. Upload local CSV file"
    print "2. Import from URL"
    print "3. Use paste method (fallback)"
    
    let choice user-input "Choose option (1, 2, or 3):"
    
    if choice = "1" [
        load-csv-from-local-file
    ]
    if choice = "2" [
        load-csv-from-url
    ]
    if choice = "3" or choice = false [
        load-student-csv-enhanced
    ]
end

;; Load CSV from local file upload
to load-csv-from-local-file
  carefully [
    print "Please select your CSV file..."
    
    ;; Use fetch extension 
    fetch:user-file-async [
      content ->
        ifelse content != false [
          process-csv-content content "local file"
        ] [
          print "No file selected or file was empty."
          load-student-csv-enhanced
        ]
    ]
  ] [
    print "Error: Fetch extension not available."
    print "Falling back to paste method..."
    load-student-csv-enhanced
  ]
end

;; Load CSV from URL
to load-csv-from-url
  let url user-input "Enter the URL of your CSV file:"
  
  ifelse url != false and url != "" [
    carefully [
      print (word "Fetching CSV from: " url)
      
      ;; Use fetch extension 
      fetch:url-async url [
        content ->
          ifelse content != false [
            process-csv-content content "URL"
          ] [
            print "Could not fetch data from URL."
            load-student-csv-enhanced
          ]
      ]
    ] [
      print "Error: Could not fetch from URL."
      load-student-csv-enhanced
    ]
  ] [
    print "No URL provided."
    load-student-csv-enhanced
  ]
end

;; Process CSV content from file or URL
to process-csv-content [csv-content source-type]
  set student-data []
  let loaded-count 0
  let error-count 0
    
    print (word "Processing CSV data from " source-type "...")
    
    carefully [
        ;; Use the official CSV extension to parse the data
        let csv-data csv:from-string csv-content
        
        ;; Skip header row if it exists
        let data-rows csv-data
        if length csv-data > 0 [
        let first-row item 0 csv-data
        if length first-row >= 2 [
            let first-name item 0 first-row
            let first-type item 1 first-row
            ;; Check if first row looks like a header
            if (first-name = "Name" or first-name = "name") and 
            (first-type = "Type" or first-type = "type") [
            set data-rows but-first csv-data
            print "Header row detected and skipped."
            ]
        ]
        ]
        
        foreach data-rows [ the-row ->
        let validation-result validate-student-row the-row
        ifelse first validation-result [
            set student-data lput (last validation-result) student-data
            set loaded-count loaded-count + 1
        ] [
            set error-count error-count + 1
            if length the-row > 0 [
            print (word "Skipped invalid row: " the-row)
            ]
        ]
        ]
    ] [
        print "Error parsing CSV with official extension. Trying manual parsing..."
        
        ;; Fallback to manual parsing
        let lines split-string csv-content "\n"
        
        foreach lines [ the-line ->
        if the-line != "" and the-line != "\r" [
            let parts split-string the-line ","
            let validation-result validate-student-row parts
            ifelse first validation-result [
            set student-data lput (last validation-result) student-data
            set loaded-count loaded-count + 1
            ] [
            set error-count error-count + 1
            ]
        ]
        ]
    ]
    
    ;; Create the student panel and provide feedback
    ifelse loaded-count > 0 [
        create-student-panel
        print (word "Successfully loaded " loaded-count " students from " source-type)
    ] [
        print (word "No valid students found in " source-type)
    ]
    
    if error-count > 0 [
        print (word "Warning: " error-count " rows were skipped due to invalid format")
    ]
    
    ;; Show sample of loaded data
    if loaded-count > 0 [
        print "Sample of loaded students:"
        let sample-count min (list 3 loaded-count)
        let i 0
        while [i < sample-count] [
        let student-info item i student-data
        print (word "  " (item 0 student-info) " (" (item 1 student-info) ")")
        set i i + 1
        ]
        if loaded-count > 3 [
        print (word "  ... and " (loaded-count - 3) " more students")
        ]
    ]
end


;; Export current classroom arrangement to downloadable CSV
to export-classroom-to-file
    let arrangement-csv "Name,Type,X,Y,IsPlaced\n"
    
    ;; Add placed students
    ask students [
        set arrangement-csv (word arrangement-csv student-name "," student-type "," xcor "," ycor ",true\n")
    ]
    
    ;; Add unplaced students from panel
    foreach student-data [ student-info ->
        let name item 0 student-info
        let type-str item 1 student-info
        
        ;; Check if this student is already placed
        let is-placed false
        ask students [
        if student-name = name and student-type = type-str [
            set is-placed true
        ]
        ]
        
        if not is-placed [
        set arrangement-csv (word arrangement-csv name "," type-str ",,false\n")
        ]
    ]
    
    ifelse length arrangement-csv > 25 [  ;; More than just the header
        print "=== CLASSROOM ARRANGEMENT (CSV) ==="
        print arrangement-csv
        print "=================================="
        print "Copy the above text and save it as a .csv file"
    ] [
        print "No student data to export."
    ]
end

;; =================================================================
;; CSV PROCESSING PROCEDURES
;; =================================================================


to load-student-csv-enhanced
    ;; Provide clear instructions to the user
    let instructions "Please paste your CSV data below.\n\nFormat: Name,Type (one student per line)\nExample:\nJohn Smith,disruptive\nMary Johnson,quiet\nBob Wilson,talkative\n\nSupported types: disruptive, quiet, talkative"
    
    let csv-input user-input instructions
    
    if csv-input != false and csv-input != "" [
        process-csv-content csv-input "pasted data"
    ]
end

;; Original simple CSV loader (for backward compatibility)
to load-student-csv
    ;; Simple CSV loader - kept for compatibility
    let csv-input user-input "Paste your CSV data (Name,Type format, one line per student):"
    
    if csv-input != false and csv-input != "" [
        set student-data []
        
        ;; Try to use the official CSV extension first
        carefully [
        let csv-data csv:from-string csv-input
        
        foreach csv-data [ the-row ->
            if length the-row >= 2 [
            let name item 0 the-row
            let type-str item 1 the-row
            
            ;; Clean up the strings
            set name trim-string name
            set type-str trim-string type-str
            set type-str string-downcase type-str
            
            ;; Add to student data
            set student-data lput (list name type-str) student-data
            ]
        ]
        ] [
        ;; Fallback to manual parsing
        let lines split-string csv-input "\n"
        
        foreach lines [ the-line ->
            if the-line != "" [
            let parts split-string the-line ","
            if length parts >= 2 [
                let name item 0 parts
                let type-str item 1 parts
                
                set name trim-string name
                set type-str trim-string type-str
                set type-str string-downcase type-str
                
                set student-data lput (list name type-str) student-data
            ]
            ]
        ]
        ]
        
        create-student-panel
        print (word "Loaded " length student-data " students from CSV")
    ]
end

;; Validate and clean a single student row from CSV
to-report validate-student-row [row]
    if length row < 2 [
        report (list false [])
    ]
    
    let name item 0 row
    let type-str item 1 row
    
    ;; Clean up the strings
    set name trim-string name
    set type-str trim-string type-str
    set type-str string-downcase type-str
    
    ;; Validate that we have non-empty values
    if name = "" or type-str = "" [
        report (list false [])
    ]
    
    ;; Validate and normalize student type
    let valid-types ["disruptive" "quiet" "talkative"]
    if not member? type-str valid-types [
        ;; Try to match partial or similar types
        if member? "disrupt" type-str or member? "noisy" type-str [
        set type-str "disruptive"
        ]
        if member? "talk" type-str or member? "chat" type-str [
        set type-str "talkative"
        ]
        
        ;; If still not valid, default based on common patterns
        if not member? type-str valid-types [
        if type-str = "blue" or type-str = "1" [
            set type-str "disruptive"
        ]
        if type-str = "107" or type-str = "2" [
            set type-str "talkative"
        ]
        if type-str = "white" or type-str = "0" or type-str = "3" [
            set type-str "quiet"
        ]
        ]
        
        ;; Final fallback
        if not member? type-str valid-types [
        set type-str "quiet"
        ]
    ]
    
    report (list true (list name type-str))
end

to create-student-panel
  ;; clear panel turtles and any labels below the line (keep the title on the line)
  ask panel-students [ die ]
  ask patches with [pycor < panel-line-y and plabel != "" ] [ set plabel "" ]

  ;; order: disruptive -> talkative -> quiet
  set student-data sort-student-data student-data
  let ordered-students student-data
  if length ordered-students = 0 [ stop ]

  ;; title on the white line
  ask patch 0 panel-line-y [
    set plabel "STUDENT PANEL"
    set plabel-color red
  ]

  ;; build row y-values (every 2 patches below the panel line)
  let row-ys []
  let y (panel-line-y - 1)
  while [y >= (min-pycor + 1)] [
    set row-ys lput y row-ys
    set y (y - 2)
  ]
  if empty? row-ys [
    print "Panel line too low; raise it (e.g., move-panel-line 2) or increase world height."
    stop
  ]

  let nD length filter [r -> item 1 r = "disruptive"] ordered-students
  let nT length filter [r -> item 1 r = "talkative"]  ordered-students
  let nQ length filter [r -> item 1 r = "quiet"]      ordered-students
  let groups 0
  if nD > 0 [ set groups groups + 1 ]
  if nT > 0 [ set groups groups + 1 ]
  if nQ > 0 [ set groups groups + 1 ]
  let nGaps max list 0 (groups - 1)

  ;; ===================== spacing controls =====================
  let leftMargin  4       ;; pull panel in from left edge 
  let rightMargin 4       ;; pull panel in from right edge 
  let spacer      1       ;; columns between different type groups 
  let minStep     3       ;; minimum horizontal spacing between dots (>=3 prevents label overlap)
  ;; ========================================================================

  ;; horizontal bounds with margins
  set panel-x (min-pxcor + leftMargin)
  let xmax (max-pxcor - rightMargin)

  ;; total columns to fit: students + the group-gap columns
  let need-cols (length ordered-students + spacer * nGaps)


  let step 5
  while [ step > minStep and
          ((max list 1 (floor ((xmax - panel-x) / step) + 1)) * length row-ys) < need-cols ] [
    set step (step - 1)
  ]
  let per-row max list 1 (floor ((xmax - panel-x) / step) + 1)

  ;; adapt dot size & label length to density
  let dot-size     (ifelse-value (step >= 4) [1.35] [(ifelse-value (step = 3) [1.2] [1.0])])
  let short-label? (step <= 2)   ;; with minStep=3, you’ll usually see full names


  let col 0
  let row-idx 0
  let last-type ""
  let placed 0

  foreach ordered-students [ s ->
    let name item 0 s
    let typ  item 1 s

    ;; add a small gap when the type changes
    if (last-type != "" and typ != last-type) [ set col col + spacer ]

    ;; wrap to next row
    if col >= per-row [
      set col 0
      set row-idx row-idx + 1
    ]
    if row-idx >= length row-ys [
      print (word "Panel clipped: placed " placed " of " length ordered-students
                  ". Raise the panel line, widen the View, or reduce spacing.")
      stop
    ]

    let px (panel-x + col * step)
    let py item row-idx row-ys

    ask patch px py [
      sprout-panel-students 1 [
        setxy px py
        set shape "circle"
        set size dot-size
        set student-name name
        set student-type typ
        if typ = "disruptive" [ set color blue  ]
        if typ = "talkative"  [ set color 107   ]
        if typ = "quiet"      [ set color white ]
        set label (ifelse-value short-label?
                    [ ifelse-value (length name <= 3) [ name ] [ substring name 0 3 ] ]
                    [ name ])
        set label-color red
      ]
    ]

    set placed placed + 1
    set col col + 1
    set last-type typ
  ]
end



to-report abbrev [s n]
  report ifelse-value (length s <= n) [ s ] [ substring s 0 n ]
end





;; Trim whitespace from beginning and end of string
to-report trim-string [str]
    ;; Convert to string if it's a number
    if is-number? str [ set str (word str) ]
    if str = false [ set str "" ]
    
    ;; Remove leading spaces
    while [length str > 0 and substring str 0 1 = " "] [
        set str substring str 1 length str
    ]
    
    ;; Remove trailing spaces
    while [length str > 0 and substring str (length str - 1) length str = " "] [
        set str substring str 0 (length str - 1)
    ]
    
    ;; Also remove carriage returns and tabs
    set str replace-item-in-string str "\r" ""
    set str replace-item-in-string str "\t" ""
    
    report str
end

;; Clear old static panel elements
to clear-old-static-panel
  ;; Remove all old labels
  ask patches with [plabel != ""] [
    set plabel ""
  ]
  
  ;; Remove any existing turtles (students, teachers, tables) 
  ask turtles [
    die
  ]
end

;; Refresh the student panel display
to refresh-student-panel
  if length student-data > 0 [
    create-student-panel
  ]
end

;; =================================================================
;; FETCH EXTENSION TEST PROCEDURES
;; =================================================================

;; Test fetch extension user file async
to test-fetch-user-file-async
  clear-all
  fetch:user-file-async [
    text ->
      show text
  ]
end

;; Test fetch extension URL async
to test-fetch-url-async
  clear-all
  let test-url user-input "Enter URL to test:"
  if test-url != false and test-url != "" [
    fetch:url-async test-url [
      text ->
        show text
    ]
  ]
end

;; =================================================================

;; Replace all occurrences of a character in a string (NetLogo Web compatible)
to-report replace-item-in-string [str old-char new-char]
  let result ""
  let i 0
  while [i < length str] [
    let char substring str i (i + 1)
    ifelse char = old-char [
      set result (word result new-char)
    ] [
      set result (word result char)
    ]
    set i i + 1
  ]
  report result
end
;;==============================================================================
;; OPTIMIZATION TOOLKIT 
;;==============================================================================

;;Setup helpers
to opt-setup
  ;; weights for seat sensitivity
  set alpha-dist 0.5
  set beta-neigh 1.2
  opt-build-seats
  opt-compute-seat-sensitivity
  opt-build-student-risks
  opt-build-seeds 50     
end

to opt-build-student-risks
  ask students with [ycor > -22] [
    let t student-type
    if t = "" [
      ;; fallback by color if type string isn't set
      if color = blue  [ set t "disruptive" ]
      if color = 107   [ set t "talkative"  ]
      if color = white [ set t "quiet"      ]
    ]
    set risk (ifelse-value (t = "disruptive") [3]
               [t = "talkative"]             [2]
                                            [1])
  ]
end


to opt-build-seats
  set seats-list []
  ask students with [ycor > -22] [
    set seats-list lput (list round xcor round ycor) seats-list
  ]
  ;; deterministic order: by y then x
  set seats-list sort-by
    [[a b] -> ifelse-value ((last a) = (last b))
                      [ (first a) < (first b) ]
                      [ (last a)  < (last b) ]]
    seats-list
end

to-report opt-dist-xy-xy [xy1 xy2]
  let dxv (item 0 xy1) - (item 0 xy2)   ;; was: dx
  let dyv (item 1 xy1) - (item 1 xy2)   ;; was: dy
  report sqrt (dxv * dxv + dyv * dyv)
end


to opt-compute-seat-sensitivity
  set seats-sens-list []
  let hasT any? teachers with [ycor > -22]
  let tx 0
  let ty 0
  if hasT [
    let t one-of teachers with [ycor > -22]
    set tx [xcor] of t
    set ty [ycor] of t
  ]

  let N length seats-list ;; number of candidate seats

  foreach seats-list [ xy ->
    let x item 0 xy
    let y item 1 xy
    let dist-teacher (ifelse-value hasT
                        [ sqrt ((x - tx) * (x - tx) + (y - ty) * (y - ty)) ]
                        [ 1e9 ])     ;; effectively "very far" if no teacher

    ;; neighbors actually within radius
    let neigh 0
    foreach seats-list [ xy2 ->
      if xy2 != xy [
        if opt-dist-xy-xy xy xy2 <= radius-of-influence [
          set neigh neigh + 1
        ]
      ]
    ]

    ;; normalize
    let maxNeigh max list 1 (N - 1)      ;; avoid divide-by-zero
    let neighFrac neigh / maxNeigh       

    ; lower = safer seat
    let sens (beta-neigh * neighFrac
              - alpha-dist / (max (list dist-teacher 0.1)))

    set seats-sens-list lput (list xy sens) seats-sens-list
  ]

  ;; sort ascending: safest seats first
  set seats-sens-list sort-by [[a b] -> (last a) < (last b)] seats-sens-list
end








to opt-build-seeds [R]
  set rng-seeds []
  let base 123456
  let i 0
  while [i < R] [
    set rng-seeds lput (base + i * 9973) rng-seeds
    set i i + 1
  ]
end


to opt-apply-type-assignment [ seatTypeList ]
  foreach seatTypeList [ row ->
    let xy item 0 row
    let t  item 1 row
    ;; find the student currently at that seat
    ask students with [ycor > -22
                       and round xcor = (item 0 xy)
                       and round ycor = (item 1 xy)] [
      if t = "disruptive" [
        set color blue
        set student-type "disruptive"
      ]
      if t = "talkative" [
        set color 107
        set student-type "talkative"
      ]
      if t = "quiet" [
        set color white
        set student-type "quiet"
      ]
      set-probabilities-by-color
      set risk (ifelse-value (student-type = "disruptive") [3]
                 [student-type = "talkative"]             [2]
                                                          [1])
    ]
  ]
end

;move turtles to seats when needed 
to opt-apply-student-assignment [ seatWhoList ]
  let i 0
  while [i < length seatWhoList] [
    let row item i seatWhoList
    let xy  item 0 row
    let wid item 1 row
    let tx  item 0 xy
    let ty  item 1 xy
    if turtle wid != nobody [
      let t turtle wid
      if (round [xcor] of t != tx) or (round [ycor] of t != ty) [
        let occ one-of students with [ ycor > -22 and round xcor = tx and round ycor = ty ]
        ifelse occ = nobody [
          ask t [ setxy tx ty ]
        ] [
          let ox [xcor] of t
          let oy [ycor] of t
          ask t   [ setxy tx ty ]
          ask occ [ setxy ox oy ]
        ]
      ]
    ]
    set i i + 1
  ]
  display
end
;;;;;;;;;;;;;;;;;;;;;;;;
;; Save/restore in-class students (position + type + color)
to-report opt-snapshot-state
  let snap []
  ask students with [ycor > -22] [
    set snap lput (list who xcor ycor student-type color label) snap
  ]
  report snap
end

to opt-restore-state [snap]
  foreach snap [ rec ->
    let w   item 0 rec
    let x   item 1 rec
    let y   item 2 rec
    let t   item 3 rec
    let c   item 4 rec
    let lbl item 5 rec
    if turtle w != nobody [
      ask turtle w [
        setxy x y
        set student-type t
        set color c
        set label lbl
        set-probabilities-by-color
        set risk (ifelse-value (t = "disruptive") [3]
                 [t = "talkative"]             [2]
                                             [1])
        set size 1
        set bother? 0
      ]
    ]
  ]
end


;;;;;;;;;;;;;;;;;;;;;;;;

;;Evaluator with CRN
to-report opt-evaluate [nR nTicks useTypes? assignmentList]
  if length rng-seeds < nR [ opt-build-seeds nR ]
  let scores []

  ;;no plotting during evaluation
  let prevFast opt-fast?
  set opt-fast? true

  ;; snapshot original world once
  let base opt-snapshot-state

  let r 0
  while [r < nR] [
    ;; restore original state at the start of each replicate
    opt-restore-state base
    random-seed (item r rng-seeds)

    ;; reset per-run state
    set noise-history []
    set total-noise 0
    set opt-sum-noise 0
    set opt-step-count 0
    ask students [ set size 1 set bother? 0 ]
    reset-ticks

    ;; apply the candidate assignment 
    ifelse useTypes? [
      opt-apply-type-assignment assignmentList   ;; TEMP repaint
    ] [
      opt-apply-student-assignment assignmentList ;; TEMP move
    ]

    ;; run exactly nTicks steps
    let t 0
    while [t < nTicks] [
      go-once
      set t t + 1
    ]

    set scores lput total-noise scores
    set r r + 1
  ]

  ;; restore original world after all reps
  opt-restore-state base
  set opt-fast? prevFast
  reset-ticks
  report mean scores
end





to-report opt-baseline-greedy-2swap [nR nTicks]

  opt-build-seats
  opt-compute-seat-sensitivity
  opt-build-student-risks
  if length rng-seeds < nR [ opt-build-seeds nR ]

  ;; seats safest-first
  let ordered-seats map [p -> first p] seats-sens-list

  ;; students riskiest-first (tie-break by who for determinism)
  let studs students with [ycor > -22]
  let ordered-studs sort-by
    [[a b] ->
      ifelse-value ([risk] of b != [risk] of a)
        [[risk] of b < [risk] of a]
        [[who] of a < [who] of b]
    ] studs


  let assign []
  (foreach ordered-seats ordered-studs
    [ [xy s] -> set assign lput (list xy [who] of s) assign ])

  ;; Evaluate the seed
  let best-assign assign
  let best-score opt-evaluate nR nTicks false assign

  let seat-types []
  let i 0
  let N length best-assign
  while [i < N] [
    let who-i last (item i best-assign)
    set seat-types lput (ifelse-value (turtle who-i != nobody)
                              [[student-type] of turtle who-i]
                              ["quiet"]) seat-types
    set i i + 1
  ]

  let improved true
  while [improved] [
    set improved false

    set i 0
    while [i < (N - 1)] [
      let type-i item i seat-types

      let j (i + 1)
      while [j < N] [
        let type-j item j seat-types

        ;;swapping same-type students leaves type layout 
        if type-i != type-j [
          ;; build candidate by swapping at seats i and j
          let a1 item i best-assign
          let a2 item j best-assign
          let cand best-assign
          set cand replace-item i cand (list (item 0 a1) (last a2))
          set cand replace-item j cand (list (item 0 a2) (last a1))

          ;; evaluate candidate via simulation (CRN)
          let sc opt-evaluate nR nTicks false cand

          if sc + 1e-9 < best-score [
            set best-score sc
            set best-assign cand

            let tmpT type-i
            set seat-types replace-item i seat-types type-j
            set seat-types replace-item j seat-types tmpT

            set improved true

            ;; first-improvement
            set j N
            set i N
          ]
        ]

        set j j + 1
      ]
      set i i + 1
    ]
  ]

  report (list best-assign best-score)
end


;; ======== Plain Brute Force ========
to opt-bf-rec [i remD remT remQ]
  if i = bf-M [

    let assign []
    let k 0
    while [k < bf-M] [
      set assign lput (list (item k seats-list) (item k bf-partial)) assign
      set k k + 1
    ]
    let sc opt-evaluate bf-R bf-nTicks true assign
    if sc < bf-best-score [
      set bf-best-score sc
      set bf-best-assign assign
    ]
    stop
  ]

  if remD > 0 [
    set bf-partial replace-item i bf-partial "disruptive"
    opt-bf-rec (i + 1) (remD - 1) remT remQ
    set bf-partial replace-item i bf-partial ""
  ]
  if remT > 0 [
    set bf-partial replace-item i bf-partial "talkative"
    opt-bf-rec (i + 1) remD (remT - 1) remQ
    set bf-partial replace-item i bf-partial ""
  ]
  if remQ > 0 [
    set bf-partial replace-item i bf-partial "quiet"
    opt-bf-rec (i + 1) remD remT (remQ - 1)
    set bf-partial replace-item i bf-partial ""
  ]
end

;; ======= HELPERS =======
to-report opt-current-type-counts
  ;; returns [nD nT nQ] from currently placed students (y > -22)
  let nD count students with [ycor > -22 and student-type = "disruptive"]
  let nT count students with [ycor > -22 and student-type = "talkative"]
  let nQ count students with [ycor > -22 and student-type = "quiet"]
  report (list nD nT nQ)
end

to opt-run-baseline [nR nTicks]
  ;; Greedy + 2-swap over individual students; applies result.
  opt-setup
  reset-timer
  let res (opt-baseline-greedy-2swap nR nTicks)  ;; res = [assignment score]
  let elapsed timer
  opt-apply-student-assignment (first res)
  print (word "[Baseline]  R=" nR " ticks=" nTicks
              "  score=" precision (last res) 3
              "  time(s)=" precision elapsed 3)
end

to opt-run-bruteforce-auto [nR nTicks]
  ;; Brute-force over *types* using current (D,T,Q) counts; applies result.
  opt-setup
  let counts opt-current-type-counts
  let nD item 0 counts
  let nT item 1 counts
  let nQ item 2 counts
  reset-timer
  let res (opt-bruteforce-types nD nT nQ nR nTicks)  ;; res = [assignment score]
  let elapsed timer
  opt-apply-type-assignment-move (first res)
  print (word "[BruteForce] D=" nD " T=" nT " Q=" nQ
              "  R=" nR " ticks=" nTicks
              "  score=" precision (last res) 3
              "  time(s)=" precision elapsed 3)
end

to opt-benchmark-both [nR nTicks]
  ;; Runs both (baseline first, then brute force on current counts) and prints times.
  ;; Applies the *last* one run (brute force). Use the two runners separately if you
  ;; want to leave the room in the baseline layout.
  opt-setup
  reset-timer
  let res1 (opt-baseline-greedy-2swap nR nTicks)
  let t1 timer
  print (word "[Baseline]  R=" nR " ticks=" nTicks
              "  score=" precision (last res1) 3
              "  time(s)=" precision t1 3)

  let counts opt-current-type-counts
  let nD item 0 counts
  let nT item 1 counts
  let nQ item 2 counts
  reset-timer
  let res2 (opt-bruteforce-types nD nT nQ nR nTicks)
  let t2 timer
  print (word "[BruteForce] D=" nD " T=" nT " Q=" nQ
              "  R=" nR " ticks=" nTicks
              "  score=" precision (last res2) 3
              "  time(s)=" precision t2 3)

  ;; choose which to apply here we apply the better (lower score)
  ifelse (last res1) <= (last res2) [
    opt-apply-student-assignment (first res1)
    print "[Applied] Baseline layout (lower score)"
  ] [
    opt-apply-type-assignment-move (first res2)
    print "[Applied] Brute-force (types) layout (lower score)"
  ]
end
to-report opt-bruteforce-types [nD nT nQ nR nTicks]
  opt-build-seats
  if length rng-seeds < nR [ opt-build-seeds nR ]

  set bf-M length seats-list
  set bf-partial n-values bf-M [""]
  set bf-best-score 1e+99
  set bf-best-assign []
  set bf-R nR
  set bf-nTicks nTicks

  opt-bf-rec 0 nD nT nQ
  report (list bf-best-assign bf-best-score)
end
;; ========- size estimation for brute force ========
to-report opt-log-factorial [n]
  let acc 0
  let k 2
  while [k <= n] [
    set acc acc + (ln k)
    set k k + 1
  ]
  report acc
end

to-report opt-log-multinomial [nD nT nQ]
  let m (nD + nT + nQ)
  report (opt-log-factorial m)
       - (opt-log-factorial nD)
       - (opt-log-factorial nT)
       - (opt-log-factorial nQ)
end

to-report opt-sci-from-ln [lnx]
  let ln10 (ln 10)
  let k floor (lnx / ln10)
  let mantissa exp (lnx - k * ln10)
  report (word precision mantissa 3 "e" k)
end

to opt-bench-evaluate-one [nR nTicks]
  opt-setup
  ;; type assignment matching current seating
  let assign []
  foreach seats-list [xy ->
    let stu one-of students with [ycor > -22
                                  and round xcor = (item 0 xy)
                                  and round ycor = (item 1 xy)]
    if stu != nobody [
      set assign lput (list xy [student-type] of stu) assign
    ]
  ]
  reset-timer
  let sc opt-evaluate nR nTicks true assign
  print (word "Evaluate-one: score=" precision sc 3 "  time=" precision timer 3 "s")
end


to opt-bench-baseline [nR nTicks]
  opt-setup
  reset-timer
  let res opt-baseline-greedy-2swap nR nTicks
  print (word "Baseline: score=" precision (last res) 3 "  time=" precision timer 3 "s")
end

to opt-bench-bruteforce [nD nT nQ nR nTicks]
  opt-setup
  reset-timer
  let res opt-bruteforce-types nD nT nQ nR nTicks
  print (word "Bruteforce: score=" precision (last res) 3 "  time=" precision timer 3 "s")
end
to-report opt-current-seatwho
  let res []
  ask students with [ycor > -22] [
    set res lput (list (list round xcor round ycor) who) res
  ]
  report res
end

;; Build a seat -> type plan from the current room (feasible seed for UB)
to-report opt-current-seat-type-plan
  let plan []
  foreach seats-list [ xy ->
    let occ one-of students with
      [ ycor > -22 and round xcor = (item 0 xy) and round ycor = (item 1 xy) ]
    let t "quiet"
    if occ != nobody [ set t [student-type] of occ ]
    set plan lput (list xy t) plan
  ]
  report plan
end


to opt-print-moves [target]   ;; target is [(xy) who] like the optimizer returns
  let changes 0
  foreach target [ row ->
    let xy item 0 row
    let w  item 1 row
    let occ one-of students with [ycor > -22 and round xcor = (item 0 xy) and round ycor = (item 1 xy)]
    if occ != nobody and [who] of occ != w [
      set changes changes + 1
      print (word "Move " [student-name] of turtle w " (who=" w ")  ->  " xy)
    ]
  ]
  if changes = 0 [ print "No seat changes (best assignment matches current layout)." ]
  print (word "Total planned moves: " changes)
end

to opt-run-baseline-apply-with-preview [nR nTicks]
  opt-setup
  let res (opt-baseline-greedy-2swap nR nTicks)
  print (word "[Baseline] score=" precision (last res) 3)
  print "Planned moves:"
  opt-print-moves (first res)
  opt-apply-student-assignment (first res)
end
to opt-run-baseline-button [nR nTicks]
  opt-setup
  reset-timer
  let res (opt-baseline-greedy-2swap nR nTicks)   ;; [assignment score]
  let elapsed timer
  opt-apply-student-assignment (first res)
  let typePlan  opt-current-seat-type-plan
  let typeScore opt-evaluate nR nTicks true typePlan

  set opt-last-method "Greedy + 2-swap (reported as types)"
  set opt-last-score  typeScore
  set opt-last-time   elapsed

  print (word "[Baseline]  R=" nR " ticks=" nTicks
              "  score=" precision typeScore 3
              "  time(s)=" precision elapsed 3)
end

to opt-run-bruteforce-button [nR nTicks]
  ;; Brute force over types using current counts
  opt-setup
  let counts opt-current-type-counts
  let nD item 0 counts
  let nT item 1 counts
  let nQ item 2 counts

  let lnN opt-log-multinomial nD nT nQ
  let maxLn 14.9   ;; ≈ 3e6 arrangements; adjust if needed
  if lnN > maxLn [
    set opt-last-method "Brute force (types)"
    set opt-last-score -1
    set opt-last-time 0
    set opt-last-note (word "Skipped: ~" (opt-sci-from-ln lnN) " arrangements")
    print (word "[BruteForce] Too large: ~" (opt-sci-from-ln lnN) " arrangements. Skipped.")
    stop
  ]

  reset-timer
  let res (opt-bruteforce-types nD nT nQ nR nTicks)   ;; [assignment score]
  let elapsed timer
  opt-apply-type-assignment-move (first res)
  set opt-last-method "Brute force (types)"
  set opt-last-score (last res)
  set opt-last-time elapsed
  set opt-last-note (word "Applied seat→type assignment (D=" nD ", T=" nT ", Q=" nQ ")")
  print (word "[BruteForce] D=" nD " T=" nT " Q=" nQ
              "  R=" nR " ticks=" nTicks
              "  score=" precision opt-last-score 3
              "  time(s)=" precision opt-last-time 3)
end

to opt-benchmark-both-button [nR nTicks]
  opt-setup

  reset-timer
  let res1 (opt-baseline-greedy-2swap nR nTicks)
  let t1 timer
  print (word "[Baseline]  R=" nR " ticks=" nTicks
              "  score=" precision (last res1) 3
              "  time(s)=" precision t1 3)

  let counts opt-current-type-counts
  let nD item 0 counts
  let nT item 1 counts
  let nQ item 2 counts
  let lnN opt-log-multinomial nD nT nQ
  let maxLn 14.9

  ifelse lnN <= maxLn [
    reset-timer
    let res2 (opt-bruteforce-types nD nT nQ nR nTicks)
    let t2 timer
    print (word "[BruteForce] D=" nD " T=" nT " Q=" nQ
                "  R=" nR " ticks=" nTicks
                "  score=" precision (last res2) 3
                "  time(s)=" precision t2 3)

    ifelse (last res1) <= (last res2) [
      opt-apply-student-assignment (first res1)
      set opt-last-method "Benchmark → applied Greedy + 2-swap"
      set opt-last-score (last res1)
      set opt-last-time t1
      set opt-last-note "Lower score than brute force"
      print "[Applied] Baseline layout (lower score)"
    ] [
      opt-apply-type-assignment-move (first res2)
      set opt-last-method "Benchmark → applied Brute force (types)"
      set opt-last-score (last res2)
      set opt-last-time t2
      set opt-last-note "Lower score than baseline"
      print "[Applied] Brute-force (types) layout (lower score)"
    ]
  ] [
    print (word "[BruteForce] Skipped: ~" (opt-sci-from-ln lnN) " arrangements (too large).")
    opt-apply-student-assignment (first res1)
    set opt-last-method "Benchmark → applied Greedy + 2-swap"
    set opt-last-score (last res1)
    set opt-last-time t1
    set opt-last-note "Brute force skipped (too large)"
    print "[Applied] Baseline layout"
  ]
end


to-report opt-build-seatwho-from-seattype [seatTypeList]

  let result []
  let used   []  

  let i 0
  while [i < length seatTypeList] [
    let row item i seatTypeList
    let xy  item 0 row
    let t   item 1 row

    let occ one-of students with
      [ ycor > -22
        and round xcor = (item 0 xy)
        and round ycor = (item 1 xy)
        and student-type = t ]

    ifelse (occ != nobody and not member? ([who] of occ) used) [
      set result lput (list xy ([who] of occ)) result
      set used   lput ([who] of occ) used
    ] [
      set result lput (list xy nobody) result
    ]
    set i i + 1
  ]

  set i 0
  while [i < length seatTypeList] [
    if (last (item i result)) = nobody [
      let row item i seatTypeList
      let xy  item 0 row
      let t   item 1 row

      let pool (students with [ ycor > -22 and student-type = t and (not member? who used) ])
      if any? pool [
        ;; choose the unused student of type t that minimizes cost in this seat
        let best min-one-of pool [ opt-seat-cost self xy ]
        set result replace-item i result (list xy ([who] of best))
        set used   lput ([who] of best) used
      ]
    ]
    set i i + 1
  ]

  report result
end

;;;;
;; Simple weight for a type (used in bounds / readability)
to-report opt-risk-weight-of-type [t]
  if t = "disruptive" [ report 3 ]
  if t = "talkative"  [ report 2 ]
  report 1
end

;; Cheap lower bound for “remaining seats”: place D then T then Q
;; onto the safest remaining seats (by sensitivity list).
to-report opt-bnb-seed-proxy [nD nT nQ]
  let lb 0
  let i 0
  while [i < bnb-M] [
    let s item i bnb-seat-sens
    if (i < nD)                    [ set lb lb + 3 * s ]
    if (i >= nD) and (i < nD + nT) [ set lb lb + 2 * s ]
    if (i >= nD + nT)              [ set lb lb + 1 * s ]
    set i i + 1
  ]
  report lb
end

to-report opt-seat-sensitivity-of [xy]
  ;; xy is a two-item list (x y). Look up its sensitivity in seats-sens-list.
  let s 10
  foreach seats-sens-list [row ->
    if (item 0 row) = xy [ set s (last row) ]
  ]
  report s
end

to-report opt-seat-cost [stu xy]
  ;; "how bad" this student is in this seat. Lower is better.
  let t [student-type] of stu
  report (opt-risk-weight-of-type t) * (opt-seat-sensitivity-of xy)
end

;;;;

;;BnB init: order seats by safety (safest first)
to opt-bnb-init [nD nT nQ nR nTicks maxNodes maxSeconds]
  ;;basics
  opt-build-seats
  opt-compute-seat-sensitivity

  set bnb-seats      map [p -> first p] seats-sens-list
  set bnb-seat-sens  map [p -> last  p] seats-sens-list
  set bnb-M          length bnb-seats
  set bnb-partial    n-values bnb-M [ "" ]
  set bnb-R          nR
  set bnb-nTicks     nTicks
  set bnb-visited    0
  set bnb-pruned     0
  set bnb-max-nodes  maxNodes

  set bnb-deadline   (ifelse-value (maxSeconds > 0) [ maxSeconds ] [ 0 ])

  ;; save initial counts for DP
  set bnb-d0 nD
  set bnb-t0 nT

  ;;per-seat admissible LB deltas: p_min = max(0, sp - tp/dist)/100 
  let hasT any? teachers with [ycor > -22]
  let tx 0
  let ty 0
  if hasT [
    let t one-of teachers with [ycor > -22]
    set tx [xcor] of t
    set ty [ycor] of t
  ]

  let spD blue-spontaneous-bother-probability
  let tpD blue-teacher-proximity-bother-probability
  let spT light-blue-spontaneous-bother-probability
  let tpT light-blue-teacher-proximity-bother-probability
  let spQ white-spontaneous-bother-probability
  let tpQ white-teacher-proximity-bother-probability

  set bnb-seat-lb-D []
  set bnb-seat-lb-T []
  set bnb-seat-lb-Q []

  foreach bnb-seats [ xy ->
    let x item 0 xy
    let y item 1 xy
    let dist (ifelse-value hasT
                [ sqrt ((x - tx) * (x - tx) + (y - ty) * (y - ty)) ]
                [ 1e9 ])
    let denom max list dist 0.1
    set bnb-seat-lb-D lput (max list 0 ((spD - (tpD / denom)) / 100)) bnb-seat-lb-D
    set bnb-seat-lb-T lput (max list 0 ((spT - (tpT / denom)) / 100)) bnb-seat-lb-T
    set bnb-seat-lb-Q lput (max list 0 ((spQ - (tpQ / denom)) / 100)) bnb-seat-lb-Q
  ]

  ;;DP and tables
  set bnb-lb-dp       n-values (bnb-M + 1)
                        [ i -> n-values (bnb-d0 + 1)
                                [ d -> n-values (bnb-t0 + 1) [ t -> -1 ] ] ]
  set bnb-prefix-best n-values (bnb-M + 1)
                        [ i -> n-values (bnb-d0 + 1)
                                [ d -> n-values (bnb-t0 + 1) [ t -> 1e+99 ] ] ]

  ;;UB seeding
  set bnb-best-score  1e+99
  set bnb-best-assign []

  let snap opt-snapshot-state

  ;; Seed A (very cheap): deterministic "safest seats get D, then T, then Q"
  let seed-plan []
  let idx 0
  while [idx < bnb-M] [
    let t (ifelse-value (idx < nD) ["disruptive"]
             [idx < (nD + nT)] ["talkative"]
                                ["quiet"])
    set seed-plan lput (list (item idx bnb-seats) t) seed-plan
    set idx idx + 1
  ]
  if (bnb-deadline = 0) or (timer < bnb-deadline - 1e-3) [
    let seed-score opt-evaluate bnb-R bnb-nTicks true seed-plan
    if seed-score < bnb-best-score [
      set bnb-best-score  seed-score
      set bnb-best-assign seed-plan
    ]
  ]

  ;; Seed B (optional, time-permitting): current layout converted to seat -> type
  if (bnb-deadline = 0) or (timer < bnb-deadline - 1e-3) [
    let cur-plan  opt-current-seat-type-plan
    let cur-score opt-evaluate bnb-R bnb-nTicks true cur-plan
    if cur-score < bnb-best-score [
      set bnb-best-score  cur-score
      set bnb-best-assign cur-plan
    ]
  ]

  opt-restore-state snap

  ;; info only
  set bnb-best-proxy (opt-bnb-seed-proxy nD nT nQ)
  print (word "BnB initialized (admissible): UB="
              precision bnb-best-score 3
              " proxy=" precision bnb-best-proxy 3)
end

;; DP lower bound for the remaining seats (admissible).
;; Returns the minimal possible sum of per-seat p_min over seats i..end,
;; using exactly remD 'disruptive', remT 'talkative', and the rest 'quiet'.
to-report opt-bnb-remain-lb [i remD remT]
  let remQ (bnb-M - i - remD - remT)
  if remQ < 0 [ report 1e+99 ]  ;; impossible state

  ;; memo lookup
  let memo item remT item remD item i bnb-lb-dp
  if memo != -1 [ report memo ]

  if i = bnb-M [
    report (ifelse-value (remD = 0 and remT = 0 and remQ = 0) [0] [1e+99])
  ]

  let best 1e+99
  if remD > 0 [
    set best min (list best ( (item i bnb-seat-lb-D) + opt-bnb-remain-lb (i + 1) (remD - 1) remT ))
  ]
  if remT > 0 [
    set best min (list best ( (item i bnb-seat-lb-T) + opt-bnb-remain-lb (i + 1) remD (remT - 1) ))
  ]
  if remQ > 0 [
    set best min (list best ( (item i bnb-seat-lb-Q) + opt-bnb-remain-lb (i + 1) remD remT ))
  ]

  ;; memo set
  let plane  item i bnb-lb-dp
  let row    item remD plane
  set row    replace-item remT row best
  set plane  replace-item remD plane row
  set bnb-lb-dp replace-item i bnb-lb-dp plane

  report best
end

;;update on prefix LB
to-report opt-prefix-dominated? [i remD remT curPrefixLB]
  report curPrefixLB >= (item remT item remD item i bnb-prefix-best) - 1e-9
end

to opt-prefix-update! [i remD remT curPrefixLB]
  let plane  item i bnb-prefix-best
  let row    item remD plane
  let old    item remT row
  if curPrefixLB < old [
    set row   replace-item remT row curPrefixLB
    set plane replace-item remD plane row
    set bnb-prefix-best replace-item i bnb-prefix-best plane
  ]
end




;; lower bound for a partial prefix at depth i with remaining counts
;; greedily drop remaining D,T,Q onto remaining safest seats
to-report opt-bnb-proxy-lb [i remD remT remQ curProxy]
  if bnb-admissible? [
    ;; Safe, admissible bound (always <= true score)
    report 0
  ]
  ;; Heuristic mode (see section 2 below)
  let lb curProxy
  let idx i
  let tempD remD
  let tempT remT  
  let tempQ remQ
  while [idx < bnb-M] [
    let s item idx bnb-seat-sens
    ifelse (tempD > 0) [
      set lb   lb + 3 * s
      set tempD tempD - 1
    ] [
      ifelse (tempT > 0) [
        set lb   lb + 2 * s
        set tempT tempT - 1
      ] [
        if (tempQ > 0) [
          set lb   lb + 1 * s
          set tempQ tempQ - 1
        ]
      ]
    ]
    set idx idx + 1
  ]
  report lb
end



to-report opt-bnb-build-assign-from-partial
  let assign []
  let k 0
  while [k < bnb-M] [
    set assign lput (list (item k bnb-seats) (item k bnb-partial)) assign
    set k k + 1
  ]
  report assign
end

to opt-bnb-rec [i remD remT remQ curPrefixLB]
  ;; Budget guards
  if (bnb-max-nodes > 0 and (bnb-visited + bnb-pruned) >= bnb-max-nodes) [
    if not bnb-timeout-hit? [ print "Hit node budget" ]  ;; optional: once
    set bnb-timeout-hit? true
    stop
  ]

  ;; Time budget (relative to reset done in the runner)
  if (bnb-deadline > 0 and timer >= bnb-deadline) [
    if not bnb-timeout-hit? [
      set bnb-timeout-hit? true
      print "Hit time budget"
    ]
    stop
  ]

  if opt-prefix-dominated? i remD remT curPrefixLB [
    set bnb-pruned bnb-pruned + 1
    stop
  ]
  ;; record this prefix best
  opt-prefix-update! i remD remT curPrefixLB

  ;; Tight admissible LB = prefix LB + remaining-seats DP LB
  let lb (curPrefixLB + opt-bnb-remain-lb i remD remT)
  if lb >= bnb-best-score + 1e-6 [
    set bnb-pruned bnb-pruned + 1
    stop
  ]

  ;; Leaf
  if i = bnb-M [
    set bnb-visited bnb-visited + 1
    let assign opt-bnb-build-assign-from-partial
    let sc opt-evaluate bnb-R bnb-nTicks true assign
    if sc < bnb-best-score [
      set bnb-best-score sc
      set bnb-best-assign assign
      print (word "New best score: " precision sc 3)
    ]
    stop
  ]

  ;; Branch ordering by smallest per-seat p_min increment
  let dD (ifelse-value (remD > 0) [ item i bnb-seat-lb-D ] [ 1e+99 ])
  let dT (ifelse-value (remT > 0) [ item i bnb-seat-lb-T ] [ 1e+99 ])
  let dQ (ifelse-value (remQ > 0) [ item i bnb-seat-lb-Q ] [ 1e+99 ])

  let options []
  if remD > 0 [ set options lput (list dD "disruptive") options ]
  if remT > 0 [ set options lput (list dT "talkative")  options ]
  if remQ > 0 [ set options lput (list dQ "quiet")      options ]
  set options sort-by [[a b] -> (first a) < (first b)] options

  foreach options [ opt ->
    let inc first opt
    let t   last  opt
    set bnb-partial replace-item i bnb-partial t
    if t = "disruptive" [ opt-bnb-rec (i + 1) (remD - 1) remT      remQ      (curPrefixLB + inc) ]
    if t = "talkative"  [ opt-bnb-rec (i + 1) remD      (remT - 1) remQ      (curPrefixLB + inc) ]
    if t = "quiet"      [ opt-bnb-rec (i + 1) remD      remT      (remQ - 1) (curPrefixLB + inc) ]
    set bnb-partial replace-item i bnb-partial ""
  ]
end




to opt-run-bnb-button [nR nTicks]
  opt-setup
  let counts opt-current-type-counts
  let nD item 0 counts
  let nT item 1 counts
  let nQ item 2 counts

  ;;timing anchor for the whole run 
  reset-timer
  set bnb-start-time timer       ;; = 0 right after reset
  set bnb-timeout-hit? false

  ;;budgets
  let maxNodes   5000000
  let maxSeconds 300

  ;;init + UB seeding (included in total time)
  opt-bnb-init nD nT nQ nR nTicks maxNodes maxSeconds
  let t_init timer

  ;;search
  opt-bnb-rec 0 nD nT nQ 0
  let t_total  timer
  let t_search t_total - t_init

  ;;apply and log
  if length bnb-best-assign = 0 [
    print "No valid solution found by Branch & Bound!"
    stop
  ]
  opt-apply-type-assignment-move bnb-best-assign

  set opt-last-method "Branch & Bound (types)"
  set opt-last-score  bnb-best-score
  set opt-last-time   t_total
  set opt-last-note   (word "Visited=" bnb-visited " pruned=" bnb-pruned)

  print (word "[BnB]  R=" nR " ticks=" nTicks
              "  score=" precision bnb-best-score 3
              "  visited=" bnb-visited
              "  pruned=" bnb-pruned
              "  time_total(s)=" precision t_total 3
              "  time_init(s)=" precision t_init 3
              "  time_search(s)=" precision t_search 3
              (ifelse-value bnb-timeout-hit? ["  (timeout)"] [""]))
end

;;;;;;;;;;;;;;; ;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Apply a seat -> type plan by picking specific students of those types
;; and MOVING them
to opt-apply-type-assignment-move [seatTypeList]
  let seatWho (opt-build-seatwho-from-seattype seatTypeList)
  opt-apply-student-assignment seatWho
  display
end
;;;;;;;;;;;;;;;;;layout saving;;;;;;;;;;;;;;;;;;;
;; robust row reader: try csv:from-string; if it fails, do a manual split
to-report rows-from-text [txt]
  let rows []
  let parsed? false

  ;; try the CSV extension first
  carefully [
    set rows csv:from-string txt
    set parsed? true
  ] [
    ;; leave parsed? = false so we fall back
  ]

  ;; fallback: naive split 
  if not parsed? [
    set rows []
    let lines split-string txt "\n"
    let i 0
    while [i < length lines] [
      let line item i lines
      let noCR  replace-item-in-string line "\r" ""
      let clean trim-string noCR
      if clean != "" [
        set rows lput (split-string clean ",") rows
      ]
      set i i + 1
    ]
  ]

  report rows
end




to-report to-num [s]
  if s = false [ report 0 ]
  if is-number? s [ report s ]
  if s = "" [ report 0 ]
  let v 0
  carefully [ set v read-from-string s ] [ set v 0 ]
  report v
end

;; tiny helper: strip UTF-8 BOM if present
to-report strip-bom [txt]
  report txt
end


;; Clear only furniture, keep students/panel
to clear-layout-only
  ask teachers [ die ]
  ask tables   [ die ]
  ;; redraw the classroom border if you use place-class()
  if is-number? class-x and is-number? class-y [ draw-class ]
end

;; Apply one CSV row
to apply-layout-record [kind shp x y sz]
  let k string-downcase kind
  let px round x
  let py round y
  let use-size (ifelse-value (sz = 0 or sz = false) [0] [sz])

  if k = "panel-line-y" [
    set panel-line-y px
    ;; clear any old white rows, then draw the new one
    ask patches with [pycor < 0] [ if pcolor = white [ set pcolor black ] ]
    ask patches with [pycor = panel-line-y] [ set pcolor white ]
    stop
  ]

  if k = "teacher" [
    ask patch px py [
      sprout-teachers 1 [
        set shape shp
        set size (ifelse-value (use-size = 0) [6] [use-size])
      ]
    ]
    stop
  ]

  if k = "table" [
    ask patch px py [
      sprout-tables 1 [
        set shape shp
        set size (ifelse-value (use-size = 0) [4] [use-size])
      ]
    ]
    stop
  ]
end

to apply-layout-from-csv-text [txt]
  clear-layout-only

  let raw strip-bom txt
  let teacher-count 0
  let table-count   0
  let line-idx 0

  let rows []
  set rows rows-from-text raw

  foreach rows [ r ->
    set line-idx line-idx + 1
    if length r >= 1 [
      let k  (ifelse-value (length r >= 1) [ trim-string item 0 r ] [""])
      let sh (ifelse-value (length r >= 2) [ trim-string item 1 r ] [""])
      let sx (ifelse-value (length r >= 3) [ trim-string item 2 r ] [""])
      let sy (ifelse-value (length r >= 4) [ trim-string item 3 r ] [""])
      let ss (ifelse-value (length r >= 5) [ trim-string item 4 r ] [""])

      ;; skip blanks/comments/header
      let kL string-downcase k
      if not (k = "" or substring k 0 (min list 1 length k) = "#" or
              (kL = "kind" and string-downcase sh = "shape")) [
        let x  to-num sx
        let y  to-num sy
        let sz to-num ss
        apply-layout-record k sh x y sz
        if kL = "teacher" [ set teacher-count teacher-count + 1 ]
        if kL = "table"   [ set table-count   table-count   + 1 ]
      ]
    ]
  ]

  if is-number? class-x and is-number? class-y [ draw-class ]
  display
  print (word "Layout applied. Teachers=" teacher-count
              " Tables=" table-count
              " panel-line-y=" panel-line-y)
end




;; Paste loader (prints a quick preview so you know it saw your text)
to load-layout-template-paste
  let txt user-input "Paste a layout CSV (starting at 'kind,shape,x,y,size' ...):"
  if txt != false and txt != "" [
    print (word "Got CSV text, len=" length txt
                " head=\"" substring txt 0 (min list 60 length txt) "\"")
    apply-layout-from-csv-text txt
  ]
end

;; Local-file loader
to load-layout-template-local
  carefully [
    fetch:user-file-async [
      content ->
        ifelse content != false [
          print (word "Loaded file, len=" length content)
          apply-layout-from-csv-text content
        ] [
          print "No file selected or empty file."
        ]
    ]
  ] [
    print "Fetch extension not available in this runtime."
  ]
end

;; URL loader (async)
to load-layout-template-url
  let url user-input "Enter URL to a layout CSV:"
  if url = false or url = "" [ stop ]
  carefully [
    fetch:url-async url [
      content ->
        ifelse content != false [
          print (word "Fetched URL, len=" length content)
          apply-layout-from-csv-text content
        ] [
          print "Could not fetch layout from the URL."
        ]
    ]
  ] [
    print "Fetch extension not available in this runtime."
  ]
end


;;button: "evaluate"
to evaluate_types_only
  ;; make sure seats-list, sensitivities, risks, and rng-seeds exist
  opt-setup

  let nR optr
  let nTicks optTicks

  let plan opt-current-seat-type-plan
  if empty? plan [
    print "No seats found to evaluate (nothing above the panel line)."
    stop
  ]

  ;; run the evaluation using types only
  let score opt-evaluate nR nTicks true plan
  set opt-last-method "Evaluate (types only)"
  set opt-last-score score
  set opt-last-time 0
  print (word "[Evaluate-Types] R=" nR " ticks=" nTicks
              "  score=" precision score 3)
end




;; ================= SAVE LAYOUT TEMPLATE (teachers + tables + panel line) ================
to save-layout-template
  ;; Build a CSV that exactly matches what apply-layout-from-csv-text expects.
  let csv "kind,shape,x,y,size\n"
  set csv (word csv "panel-line-y,," panel-line-y ",,\n")

  ask teachers [
    set csv (word csv
      "teacher," shape "," round xcor "," round ycor "," precision size 2 "\n")
  ]
  ask tables [
    set csv (word csv
      "table," shape "," round xcor "," round ycor "," precision size 2 "\n")
  ]

  print "=== CLASS LAYOUT (CSV) ==="
  print csv
  print "=========================="
  print "Copy the text above and save it as a .csv file (UTF-8, no BOM)."
  print "Later: use Load Layout (Paste/Local/URL) to apply it."
end
@#$#@#$#@
GRAPHICS-WINDOW
285
7
751
677
-1
-1
10.17
1
10
1
1
1
0
1
1
1
-22
22
-42
22
0
0
1
ticks
30

BUTTON
70
0
180
30
(1) clean board
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
0
215
100
245
(4) run
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
4
101
290
146
(2) build the room: hover on board & move
place-class
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
200
65
280
95
erase
remove-thing
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
6
154
290
209
(3) arrange: press to arrange; press to finish
drag-turtles
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
1
426
200
614
noise
time
noise level
0
10
0
10
true
false
"" ""
PENS
"default" 1 0 -16777216 true "" "plot count turtles with [size = 3]"

MONITOR
0
623
133
668
bothering students
count turtles with [size = 3]
17
1
11

MONITOR
143
623
278
668
total average noise
total-noise
2
1
11

BUTTON
5
0
65
30
restart
reset
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
5
65
105
95
+ Teacher ↓
add-teacher
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
5
30
100
60
+ Teacher ↑
add-teacher-2
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
105
30
190
60
+Table H
add-horizontal-table
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
105
65
190
95
+ Table V
add-vertical-table
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
195
0
283
30
setup
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
205
30
280
60
Load csv
load-student-csv-from-file
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
0
385
100
415
greed+2swap
opt-run-baseline-button optR optTicks
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
5
280
135
313
optr
optr
1
100
10
1
1
NIL
HORIZONTAL

SLIDER
0
320
120
353
optticks
optticks
50
1000
600
50
1
NIL
HORIZONTAL

BUTTON
115
385
190
415
bruteforce
opt-run-bruteforce-button optR optTicks
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
210
445
290
475
benchmark
opt-benchmark-both-button optR optTicks
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
200
385
280
415
BnB
opt-run-bnb-button optr optTicks
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
105
215
180
257
save layout
save-layout-template
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
185
215
276
253
load layout
load-layout-template-local
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
155
330
225
375
score
 opt-last-score
17
1
11

BUTTON
160
270
250
306
Evalute curr
evaluate_types_only
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1
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

table-horizontal
false
0
Rectangle -13840069 true false 0 120 300 210

table-vertical
false
0
Rectangle -13840069 true false 120 0 210 300

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

teacher-table-1
false
0
Circle -955883 true false 105 90 90
Rectangle -6459832 true false 0 180 300 270

teacher-table-2
false
0
Circle -955883 true false 105 120 90
Rectangle -6459832 true false 0 30 300 120

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
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0
-0.2 0 0 1
0 1 1 0
0.2 0 0 1
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@

@#$#@#$#@
