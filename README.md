# Quiet NetLogo — Classroom Seating & Noise Simulator (NetLogo Web)
A simulator for classroom layouts and student seating to reduce noise. You’ve got three “temperaments”: disruptive (blue), talkative (light-blue, code 107), and quiet (white). Drag students and furniture around, import students from CSV, then let the optimizers suggest calmer seating plans.

## Features
- Live simulation in the browser (NetLogo Web)
- Drag & drop: students, teachers, tables a student panel lives below the white line.
- CSV import/export for students layout templates you can save and reload.
- **Optimizers:**
  - **Greedy + 2-swap** (assigns specific students to seats, then hill-climbs with 2-swaps).
  - **Brute Force over** tries all the posssible seatings (works for small classes).
  - **Branch & Bound :** Goes over all possible seatings while pruning to preserve cost/time.  
---

## Quick Start

### Run
1. Open in NetLogoWeb `https://www.netlogoweb.org/`.
2. Click **setup**.
3. Build the room by clicking the designated button and draging the mouse on the black screen above the white bar.
4. Place teacher/ students manually by using the designated buttons or loading an existing template by clicking on load layout.
5. Click on the **Load csv** and input number 1 in order to load in students from an existing csv.
6. After you see the loaded in students in the STUDENT PANEL below the whtie line click on the arrange button in order to drag and drop students into the class area (the yellow line)
7. Run the sumilation by clicking the run button or use any of the optimization methods listed above.

## CSV Formats

### Students (Name,Type)
```csv
Name,Type
Rami,disruptive
Sharon,quiet
Elias,talkative
```

### Layout (teachers, tables, panel line)
```csv
kind,shape,x,y,size
panel-line-y,, -22,,
teacher,teacher-table-1,0,-20,6
table,table-horizontal,2,3,4
...
```
---
## Detailed Explantaoin of optimization methods

### Let me start by explaining "Score":
#### what exactly is score :
During optimization, each layout is simulated for exactly nTicks steps over R replicates with common random numbers (CRN). On each tick we count how many students are bothering the score is the average per-tick bother count over the whole run, then averaged over replicates:
score = average_over_replicates( mean_over_time( #bothering_students ) )
  
## Greedy + 2-swap
#### There are three phases :
1. Seat sensitivity : Seats are sorted safest to riskiest depending on neighboor and teacher proximity.
2. Greedy seeding : build a initial assignment quickly.
3. 2 swap hill climb : repeatedly swap paris of students if that swap improves the evaluated scores and stop when swaps will improve no more.
### Phase 1 :
Before the algorithim starts the code runs 
- opt-build-seats : which collects all seat coordinates (the positions of in-class students) and sort them deterministically (by y, then x).
- opt-compute-seat-sensitivity :for each seat, compute a sensitivity value:
  - Neighbor density within radius-of-influence (weighted by beta-neigh).
  - Teacher distance effect (weighted by alpha-dist).
  - Result: smaller sensitivity = safer seat.
-opt-build-student-risks : set risk = 3/2/1 from student-type.


### Phase 2 :
- Make two lists: ordered-seats (safest toriskiest), ordered-studs (riskiest to safest).
- Pair k-th safest seat with k-th riskiest student.

#### Why this makes sense:
If your scoring were exactly risk(student) × sensitivity(seat) and independent across seats, this greedy is optimal by the rearrangement inequality: pairing largest with smallest minimizes the sum. But the actual simulation has contagion and proximity effects, so greedy is not guaranteed globally optimal but it’s a strong, cheap starting point.

### Phase 3 :
We improve the greedy plan by swapping two students at a time and keeping a swap only if it lowers the evaluated score.
#### How the Algorithim works:
1. Type pruning:  
If the two students are the same type, skip the swap. The simulation’s rules depend on the type layout a same-type swap leaves that layout unchanged, so (under common random numbers) it can’t give a strictly better expected score. Skipping these pairs removes lots of pointless evaluations.

2. First-improvement strategy:  
While scanning pairs, the first swap that improves the score is accepted immediately, and we restart a fresh pass. This typically reaches the same (or better) 2-opt local minimum in less wall time than “best-improvement” scans.

3. Fair comparisons via CRN:  
Every candidate layout is evaluated with the same random streams (common random numbers), reducing noise in the comparison and making the accept/reject decision statistically sharper. 


#### Loop:

1. Evaluate the current plan to get best-score.
2. Scan seat pairs (i, j) with i < j:
- Skip if type[i] == type[j].  
- Otherwise, swap the two students, evaluate, and if the score strictly drops, accept and restart a new pass.

3.When a full pass makes no accepted swap, stop. No single pairwise swap can improve the seating .

#### Complexity:
Complexity (Greedy + 2-swap)
Let M = seats/students, R = #replicates, T = #ticks per replicate.
  
Precomputation:
- Seat sensitivity (neighbor counts + teacher distance):O(M^2)
- Sorting seats/students:O(M log M)
  
Greedy seeding:
- Build plan (pair safest seats with riskiest students):  O(M)
- Initial evaluation (simulation):O(R · T · M^2)
  
2-swap hill climb (worst case):
- Possible pairs per pass:O(M^2)
- Cost per evaluated swap (simulation):O(R · T · M^2)
- With P passes:O(P · M^2 · R · T · M^2)
  
So we get **O(P * R * T * M^4)**


---

## Brute force 
The algorithm tries every available assignment of types to seats, evaluates each by simulation (with common random numbers), and keeps the best.

#### There are three phases :
1. Precompute.
2. Enumerate all type assignments.
3. Evaluate each plan by simulation
   
### Phase 1 :

Before searching:
1. Build seats (opt-build-seats): collect all in-class seat coordinates, ordered deterministically (by y, then x).
2. Counts (opt-current-type-counts): compute n_D, n_T, n_Q.
3. Random seeds (opt-build-seeds): set up CRN for fair comparisons.
   
### Phase 2 :
The number of available seatings = M! / n_D!n_T!n_Q!.

opt-bf-rec fills seats in a fixed order:
- At seat index i, try placing D if any remain, then T, then Q (respecting the remaining counts).
- Recurse to seat i + 1 with the updated counts.
- When i = M (all seats assigned), evaluate the plan and update the best if it beats the current best score.
  
### Phase 3 :
For each complete seating:
Build the list call opt-evaluate(nR, nTicks, true, seating).
opt-evaluate:
- Runs the stochastic simulation for exactly nTicks, across nR replicates, using common random numbers (CRN) .
- Returns the average noise.

Keep the plan with the lowest score seen so far.


#### Complexity:

Each plan requires a full simulation run: nR × nTicks steps.
M! / n_D!n_T!n_Q! * (R * T)
It takes O(M^2) work (M students * O(M) neighbors) each tick so we get:
O(M! / n_D!n_T!n_Q! * (R * T) * M^2)

---

## Branch and Bound
pick, for each seat, which type sits there disruptive, talkative, or quiet minimize the simulated average noise. The alogrithim keeps the existing counts (n_D,n_T,n_Q) and searchs over all available assignments, And then it prunes huge chunks of the search using safe lower bounds. That is the “bound” in Branch and Bound: if a partial assignment can’t possibly beat the best plan already found, don’t waste time finishing it. 

#### The two main ideas for the algorithim

**Upper bound (UB)**: score of the best complete plan we’ve seen so far.

**Lower bound (LB):** a guaranteed underestimate of the best score any completion of the current partial plan could achieve. If LB >= UB, that branch is bad prune it.

All the scores are calculted using the simulator with common random numbers (CRN) so layouts are compared fairly with low variance.

#### There are 6 phases :
1. Seat sensitivity : Seats are sorted safest to riskiest depending on neighboor and teacher proximity.(same as in the greedy + 2 swap)
2. Per-seat admissible LB contributions.
3. DP lower bound for remaining seats
4. Prefix dominance table.
5. Seed the UB (two quick plans).
6. Recursive search with pruning

### Phase 1+2+3+4+5 :
1. **Order seats by “safety.”** ( as explained before )
We compute a seat sensitivity (lower = safer) from:
- Neighbor density in the contagion radius (weight beta-neigh).
- Teacher distance effect (weight alpha-dist).
Seats are sorted safest to riskiest. Thishelps both the bounds and the search.

2. **Per-seat admissible LB contributions.**
For each seat we precompute a minimum per seat bother probability for each type (D/T/Q), using your per type spontaneous and teacher-proximity terms and the seat’s distance to the teacher. Each value is clipped at 0. So that even in the best case, a disruptive student in a risky seat will contribute at least this much expected noise. Adding all these per seat minimas gives us an safe LowerBound for pruning.
For each seat i and type t  in (D/T/Q), we precompute a per tick minimal bother probability:
```math
p min ​[i,t] = max (0 , spontaneoust​ −  teacher proximity_t/max(dist_i, 0.1)​​)/100.
```
It ignores contagion in the bound (set it to 0) because contagion can only increase noise.That makes the bound in a way never overestimates the true remaining cost.
  
3. **DP lower bound for remaining seats**
A small dynamic program computes the best possible sum of those per seat minima for the remaining seats given the remaining counts (remD,remT).
Given we have assigned the first i seats and must still place remD and remT (with remQ implied), we compute:  
LB_remain(i, remD, remT) = minimal sum of p_min over seats i ... end using exactly remD, remT, and the rest Q.


4. **Prefix dominance table**
bnb-prefix-best[i][remD][remT]
- Stores the smallest curPrefixLB ever seen when you reached state (i, remD, remT).
- If you revisit that state with an equal or worse curPrefixLB, we prune.
This helps shrink the tree. 

5. **Seed the UB (two quick plans)**
We evaluate (via simulation with CRN) two complete plans and keep the better as our initial UB:
  - Safest first fill: put all D on the safest seats, then T, then Q.
  - Current layout: score the current room.
The better of one initizalizes bnb-best-score and bnb-best-assign. A strong UB makes LB >= UB pruning trigger more often.

#### Phase 6:
The algorithim explores seats in safety order. At recursion depth i:
1. Branch (choose a type).
If we still have remD > 0, we can place D at seat i similarly for T and Q. For each type compute an increment inc = p_min[i, type], sort options by inc, and explore smallest first (early good leaves leads to tighter UB leads to more pruning).

2. Compute a safe LB for this partial assignment.
  - LB = prefix_LB + DP_LB(remaining seats & counts).
  - If LB >= UB, prune: no completion can beat what we already have.

3. Leaf (all seats assigned).
  Evaluate the complete plan with the simulator:
  - score = opt-evaluate(nR, nTicks, true, plan) with CRN.
  - If the score < UB, we update UB and store the plan.

4. Budgets
The alogrithim also has max nodes and a time deadline. If a budget hits, it stops cleanly and reports the best-so-far UB.


#### Complexity:
As stated before Brute Force explores M! / n_D!n_T!n_Q! seatings.
Branch and Bound exlores a **subset** of the above seatings , any branch with LB >= UB is discarded before simulation . This will lessen the seraches hugely.

---

## Results and demonstration :
First I Want to state that the results are very much dependent on the probablities given to the students The probabilites that we are working with at the moment are :
```nlogo
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
```
And also the weight probabilites assigned for the weights of scoring seat safety:
β × neighbor_density − α / distance_to_teacher
```nlogo
alpha-dist = 0.5
beta-neigh = 1.2
```
Experimenting with different probabilites will result in different results.

#### Below we can see an image of RoomA filed with 40 students of different types:
<img width="497" height="470" alt="Screenshot 2025-10-01 142612" src="https://github.com/user-attachments/assets/cecf8751-257c-41c7-879e-8104e164e12f" />  
  
[Evaluate-Types] R=10 ticks=600  score=13.884
  
#### I will show the results of running the class arrangement on the two algorithims that were listed before **Branch and bound** and **Greedy + 2 swap**:
  
#### After running Greedy + 2 swap algorithim on the above class seating we get the below seating arrangment with the results listed below the image.
  
<img width="444" height="417" alt="Screenshot 2025-10-01 150230" src="https://github.com/user-attachments/assets/3274c029-1d27-45ce-a5b9-4e74e32e89c1" />
  
[Baseline]  R=10 ticks=600  score=13.733  time(s)=895.471
  
#### And after running the Branch and bound algorithim on the above class seating we get the below seaing arrangment with the reults listed below the image.
  
<img width="451" height="418" alt="Screenshot 2025-10-01 144658" src="https://github.com/user-attachments/assets/793c1216-71b7-469b-a550-fd8e9b6839fb" />
  
[BnB]  R=10 ticks=600  score=13.693  visited=120  pruned=109764  time_total(s)=166.893  time_init(s)=2.745  time_search(s)=164.148
[Evaluate-Types] R=10 ticks=600 

---

#### Below we can see a picture of another classroom arrangment:
  
<img width="442" height="409" alt="image" src="https://github.com/user-attachments/assets/c1243961-d986-4782-9c66-2a898944f796" />
  
[Evaluate-Types] R=10 ticks=600  score=7.691
  
#### After applying **Branch and bound**:
  
<img width="414" height="395" alt="image" src="https://github.com/user-attachments/assets/bbdea7ff-a2f6-4d23-a15c-07319770d28b" />
  
[BnB]  R=10 ticks=600  score=7.616  visited=40  pruned=7351  time_total(s)=32.087
time_init(s)=1.54  time_search(s)=30.547
  
#### After applying **Greedy + 2 Swap**:
  
<img width="382" height="372" alt="image" src="https://github.com/user-attachments/assets/30427d74-d117-4506-b1a3-c5725c52f5f3" />

  
[Baseline]  R=10 ticks=600  score=7.631  time(s)=545.341 
  
  
#### Below we can see a picture of another classroom arrangment:
  
<img width="454" height="452" alt="image" src="https://github.com/user-attachments/assets/5c4d2b13-9ee8-4a06-b113-7aea6068005f" />
  

[Evaluate-Types] R=10 ticks=800  score=2.101


#### After applying **Branch and bound**:
<img width="410" height="430" alt="image" src="https://github.com/user-attachments/assets/8634c16a-a27a-4850-9a32-fd5d8df955a6" />
  
[BnB]  R=10 ticks=800  score=2.082  visited=3  pruned=11  time_total(s)=1.107  time_init(s)=0.449  time_search(s)=0.658
  
  
#### After applying **Greedy + 2 Swap**:
<img width="416" height="420" alt="image" src="https://github.com/user-attachments/assets/bd6a24e6-86f7-48c2-9ba3-14b9522a4f6c" />
  
[Baseline]  R=10 ticks=800  score=2.082  time(s)=2.753

---

## Explanation of the above results:
As stated before the different probabilites given to the types of students is the main factor in assigning them to the different seats
so with the numbers that we have:
- Disruptive: sp=70, ctg=60, tp=20
- Talkative: sp=50, ctg=50, tp=50
- Quiet: sp=10, ctg=30, tp=80

sp = spontaneous-bother-probability   
tp = teacher-proximity-bother-probability   
d = distance to teacher  
ctg = contagion  
   
```nlogo
bother if random 100 <
  sp + ctg * bothering_in_radius − tp / max(distance_to_teacher, 0.1)
```
  
If we ignore contagion for the moment (bothering_in_radius = 0), the base bother chance is:
```nlogo
base(d) = max(0, sp − tp/d) / 100
```
So each type gets a simple expression:
  
Talkative: sp=50, tp=50  
At d = 1: 50 − 50/1 = 0 -> ~0% base risk (teacher right there cancels it).  
d = 2: 50 − 25 = 25 -> 25% base risk.  
d = 5: 50 − 10 = 40 -> 40%.  
d = 10: 50 − 5 = 45 -> 45%.  
As d -> infinity , it approaches 50% (the teacher effect fades).  
   
Quiet: sp=10, tp=80  
d = 1: 10 − 80 = −70 -> 0%.  
d = 4: 10 − 20 = −10 -> 0%.  
d = 8: 10 − 10 = 0 -> 0%.  
d = 16: 10 − 5 = 5 -> 5%.  
  
Interpretation: near the teacher they’re basically silent far away they rise toward ~10%.
  
Disruptive: sp=70, tp=20  
d = 1: 70 − 20 = 50 -> 50%.  
d = 2: 70 − 10 = 60 -> 60%.  
d = 10: 70 − 2 = 68 -> 68%.  
  
Interpretation: proximity barely helps them they stay high almost everywhere.
    
   
Therefore the optimizer prefers:
- Put Quiet in the front (diminishes their already small risk near 0 also they will not cause contagion when thery are not even making any noise).
  
- Keep Disruptive in low-neighbor seats (edges/back) to break contagion chains proximity to the teach does not really benefit them compared to others.
  
- Place Talkative in between that some get teacher benefit, while also not holding onto the lowest neighbor seats needed by the Disruptive.
  
This is why we often see back rows filled with blue, then light-blue, then white nearest the teacher. It’s the most efficient way to reduce the sum of expected disruptions given the above probability parameters but when we cahnge those probability parameters we get drastically different results as you might imagine but I wanted to stick to them in order to remain true to the original moudle.

### why Greedy + 2 Swap and Branch and Bound give different layouts 
Greedy commits to the best local choice for the next student and gets trapped by those early commitments . BnB searches whole-room type patterns, prunes bad branches with bounds, and can trade seats across types to capture the largest total reduction in simulated noise so it often lands on a layout that looks different (and usually scores the same or better).

  
### Why disruptive sometimes look “grouped” in the last row
The algorithim is not trying to cluster them it is placing them on the longest firebreak (fewest neighbors). In many rooms that’s a continuous back edge. With radius-of-influence = 6, the back edge minimizes how many classmates are in the contagion radius.
Sticking to the original moudle funcotinality Contagion is a binary trigger:
- bothering_in_radius is 1 if there is any neighbor within radius-of-influence currently bothering, else 0. The algorithim does not sum neighbors it only checks “is there at least one?”. That makes edges/corners valuable because they reduce the chance of having any bothering neighbor.


