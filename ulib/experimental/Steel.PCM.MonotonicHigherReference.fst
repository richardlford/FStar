module Steel.PCM.MonotonicHigherReference
open Steel.PCM
open Steel.PCM.Effect
open Steel.PCM.Effect.Atomic
open Steel.PCM.Memory
open Steel.PCM.FractionalPermission
open FStar.Ghost
module Preorder = FStar.Preorder
module Q = Steel.PCM.Preorder
module M = Steel.PCM.Memory
module SB = Steel.PCM.SteelT.Basics
open FStar.Real

noeq
type history (a:Type) (p:Preorder.preorder a) =
  | Witnessed : Q.hist p -> history a p
  | Current : Q.vhist p -> perm -> history a p

let hval #a #p (h:history a p{Current? h}) : Ghost.erased a =
  match h with
  | Current h _ -> Q.curval h

let hperm #a #p (h:history a p{Current? h}) : perm =
  match h with
  | Current _ f -> f

let history_composable #a #p
  : symrel (history a p)
  = fun h0 h1 ->
    match h0, h1 with
    | Witnessed h0, Witnessed h1 ->
      Q.p_composable p h0 h1
    | Witnessed h0, Current h1 f
    | Current h1 f, Witnessed h0 ->
      Q.extends #a #p h1 h0
    | Current h0 f0, Current h1 f1 ->
      h0 == h1 /\
      (sum_perm f0 f1).v <=. 1.0R

let history_compose #a #p (h0:history a p) (h1:history a p{history_composable h0 h1})
  : history a p
  = match h0, h1 with
    | Witnessed h0, Witnessed h1 ->
      Witnessed (Q.p_op p h0 h1)
    | Current h0 f, Witnessed h1
    | Witnessed h1, Current h0 f ->
      Current (Q.p_op p h1 h0) f
    | Current h0 f0, Current _ f1 ->
      Current h0 (sum_perm f0 f1)

let unit_history #a #p : history a p = Witnessed []

let lem_is_unit #a #p (x:history a p)
  : Lemma (history_composable x unit_history /\
           history_compose x unit_history == x)
  = match x with
    | Witnessed h -> ()
    | Current h _ ->
      assert (forall (h:Q.hist p). Q.p_composable p h []);
      assert (forall (h:Q.hist p). Q.p_op p h [] == h);
      assert (forall (h:Q.vhist p). Q.extends #a #p h []);
      assert (h =!= []);
      assert (Q.extends #a #p h [])

let assoc_l #a #p (x y:history a p)
                  (z:history a p{history_composable y z /\
                                 history_composable x (history_compose y z)})
  : Lemma (history_composable x y /\
           history_composable (history_compose x y) z /\
           history_compose (history_compose x y) z ==
           history_compose x (history_compose y z))
  = ()

#push-options "--query_stats"
let assoc_r #a #p (x y:history a p)
                  (z:history a p{history_composable x y /\
                                 history_composable (history_compose x y) z})
  : Lemma (history_composable y z /\
           history_composable x (history_compose y z) /\
           history_compose (history_compose x y) z ==
           history_compose x (history_compose y z))
  = ()

#push-options "--max_fuel 2 --max_ifuel 1 --z3rlimit_factor 4"
let pcm_history #a #p : pcm (history a p) = {
  p = {
         composable = history_composable;
         op = history_compose;
         one = unit_history
      };
  comm = (fun _ _ -> ());
  assoc = assoc_l;
  assoc_r = assoc_r;
  is_unit = lem_is_unit;
}
#pop-options

let pcm_history_preorder #a #p : Preorder.preorder (history a p) =
  fun h0 h1 ->
    match h0, h1 with
    | Witnessed vh0, Witnessed vh1
    | Current vh0 _, Witnessed vh1
    | Witnessed vh0, Current vh1 _
    | Current vh0 _, Current vh1 _ ->
      vh1 `Q.extends` vh0

#push-options "--max_fuel 1 --initial_fuel 4 --max_ifuel 4 --z3rlimit_factor 4"
let pcm_history_induces_preorder #a #p
  : Lemma (Q.induces_preorder (pcm_history #a #p)
                              (pcm_history_preorder #a #p))
  = let aux (x y:history a p)
       : Lemma
         (requires frame_preserving pcm_history x y)
         (ensures (forall z. compatible pcm_history x z ==>
                        pcm_history_preorder z y))
               [SMTPat (frame_preserving pcm_history x y)]
       = let aux (z:history a p)
           : Lemma
             (requires compatible pcm_history x z)
             (ensures  pcm_history_preorder z y)
             [SMTPat (compatible pcm_history x z)]
           = match x, z with
             | Witnessed vx, Witnessed vz ->
               begin
               match vz with
               | [] ->
                 () //empty history can be extended arbitrarily

               | _ ->
                 assert (history_composable (Current vz full_perm) z);
                 assert (history_composable (Current vz full_perm) y); //since y is frame-preserving
                 assert (history_compose (Current vz full_perm) y == y);
                 //no such y exists, since y must be Current and its perm must be non-zero
                 assert false
               end

             | Current vx _, Witnessed vz ->
               //impossible, since x `op` z <> z
               assert false

             | Witnessed vx, Current vz _ ->
               assert (vz `Q.extends` vx);
               assert (history_composable z x);
               assert (history_composable z y);
               assert (history_compose z y == y);
               assert (Current? y);
               assert (history_composable (Witnessed vz) z);
               assert (history_composable (Witnessed vz) y);
               let Current vy _ = y in
               assert (vy `Q.extends` vz)

             | Current vx _, Current vz _ ->
               assert (composable pcm_history (Witnessed vz) z);
               assert (vz == vx);
               let aux (frame:history a p)
                 : Lemma
                   (requires composable pcm_history x frame /\
                             history_compose x frame == z)
                   (ensures  pcm_history_preorder z y)
                   [SMTPat (composable pcm_history x frame)]
                 = match frame with
                   | Witnessed _ ->
                     assert (z == x);
                     assert (history_compose frame y == y);
                     assert (history_compose (Witnessed vz) y == y);
                     begin
                     match y with
                     | Current vy _ ->
                       assert (vy `Q.extends` vz)
                     | Witnessed vy ->
                       assert (history_compose (Witnessed vz) y == y);
                       assert (vy == Q.p_op p vz vy);
                       Q.p_op_extends p vz vy;
                       assert (vy `Q.extends` vz)
                     end

                   | Current vframe _ ->
                     assert (vframe == vz);
                     assert (history_composable frame y);
                     assert (history_compose frame y == y);
                     assert (Current?._0 y == vz)
               in
               ()
         in
         ()
    in
    ()

#pop-options

let extend_history #a #p (h0:history a p{Current? h0})
                         (v:a{p (hval h0) v})
 : history a p
 = let Current h f = h0 in
   Current (v :: h) f

let extend_history_is_frame_preserving #a #p
                                       (h0:history a p{Current? h0 /\ hperm h0 == full_perm})
                                       (v:a{p (hval h0) v})
  : Lemma (frame_preserving pcm_history h0 (extend_history h0 v))
  = ()

let ref a p = M.ref (history a p) pcm_history

let pts_to_body #a #p (r:ref a p) (f:perm) (v:Ghost.erased a) (h:history a p) =
      M.pts_to r h `star`
      pure (Current? h /\
            hval h == v /\
            hperm h == f)

let pts_to (#a:Type) (#p:Preorder.preorder a) (r:ref a p) (f:perm) (v:Ghost.erased a) =
    h_exists (pts_to_body r f v)

assume
val intro_pure (#p:slprop) (q:prop { q })
  : SteelT unit p (fun _ -> p `star` pure q)

let alloc (#a:Type) (p:Preorder.preorder a) (v:a)
  = let h = Current [v] full_perm in
    assert (compatible pcm_history h h);
    let x : ref a p = Steel.PCM.Effect.alloc h in
    SB.h_assert (M.pts_to x h);
    intro_pure (Current? h /\
                hval h == Ghost.hide v /\
                hperm h == full_perm);
    SB.h_assert (M.pts_to x h `star`  pure (Current? h /\ hval h == Ghost.hide v /\ hperm h == full_perm));
    SB.intro_h_exists h (pts_to_body x full_perm (Ghost.hide v));
    SB.h_assert (pts_to x full_perm v);
    SB.return x

assume
val get_witness (#a:Type) (#p:a -> slprop) (_:unit)
  : SteelT (erased a) (h_exists p) (fun x -> p (Ghost.reveal x))

assume
val h_assoc_r (#p #q #r:slprop) (_:unit)
  : SteelT unit ((p `star` q) `star` r) (fun _ -> p `star` (q `star` r))

module ST = Steel.PCM.Memory.Tactics

let read_refine (#a:Type) (#q:perm) (#p:Preorder.preorder a) (#f:a -> slprop)
                (r:ref a p)
  : SteelT a (h_exists (fun (v:a) -> pts_to r q v `star` f v))
             (fun v -> pts_to r q v `star` f v)
  = let v = get_witness () in
    SB.h_assert (pts_to r q v `star` f (Ghost.reveal v));
    let h : Ghost.erased _ = SB.frame (fun _ -> get_witness #_ #(pts_to_body r q v) ()) _ in
    SB.h_assert (pts_to_body r q v h `star` f (Ghost.reveal v));
    h_assoc_r ();
    let hv = SB.frame (fun _ -> read r h) _ in
    assert (compatible pcm_history h hv);
    assume (Current? h);
    assert (hval h == hval hv);
    SB.h_admit _ _

let write (#a:Type) (#p:Preorder.preorder a) (#v:erased a)
          (r:ref a p) (x:a{p v x})
  : SteelT unit (pts_to r full_perm v)
                (fun v -> pts_to r full_perm x)
  = let h_old_e = get_witness #_ #(pts_to_body r full_perm v) () in
    SB.h_assert (pts_to_body r full_perm v (Ghost.reveal h_old_e));
    let h_old = SB.frame (fun _ -> read r h_old_e) _ in
    assert (compatible pcm_history h_old_e h_old);
    SB.h_admit _ _

let lift_fact #a #p (f:property a)
  : property (history a p)
  = fun history ->
      match history with
      | Witnessed h -> Cons? h /\ f (Cons?.hd h)
      | Current h _ -> f (hval history)

let lift_fact_is_stable #a #p (f:property a{FStar.Preorder.stable f p})
  : Lemma (FStar.Preorder.stable #(history a p)
                                 (lift_fact f)
                                 (Steel.PCM.Preorder.preorder_of_pcm pcm_history))
  = assert (FStar.Preorder.stable #(history a p) (lift_fact f) pcm_history_preorder);
    pcm_history_induces_preorder #a #p;
    Q.stability #(history a p) (lift_fact f) pcm_history_preorder pcm_history

let witnessed #a #p r fact =
  M.witnessed r (lift_fact fact)

let extract_pure #a #p #f
                 (r:ref a p)
                 (v:Ghost.erased a)
                 (h:Ghost.erased (history a p))
  : SteelT (_:unit{(Current?h /\ hval h == v /\ hperm h == f)})
           (pts_to_body r f v h)
           (fun _ -> pts_to_body r f v h)
  = SB.h_admit _ _

let get_squash (#p:prop) (_:unit{p}) : squash p = ()

let witness_thunk (#a:Type) (#pcm:Steel.PCM.pcm a)
                  (r:M.ref a pcm)
                  (fact:M.stable_property pcm)
                  (v:Ghost.erased a)
                  (_:fact_valid_compat fact v)
                  (_:unit)
  : SteelT unit (M.pts_to r v)
                (fun _ -> M.pts_to r v `star` pure (M.witnessed r fact))
  = Steel.PCM.Effect.witness r fact v ()

assume
val rearrange_pqr_prq (p q r:slprop)
  : SteelT unit ((p `star` q) `star` r)
                (fun _ -> (p `star` r) `star` q)

let frame_witness (#a:Type) (#pcm:Steel.PCM.pcm a)
                  (r:M.ref a pcm)
                  (fact:M.stable_property pcm)
                  (v:Ghost.erased a)
                  (s:fact_valid_compat fact v)
                  (p:slprop)
  : SteelT unit (M.pts_to r v `star` p)
                (fun _ -> (M.pts_to r v `star` p) `star` pure (M.witnessed r fact))
  = SB.frame (witness_thunk r fact v s) _;
    rearrange_pqr_prq _ _ _


let witness (#a:Type) (#q:perm) (#p:Preorder.preorder a) (r:ref a p)
            (fact:stable_property p)
            (v:Ghost.erased a)
            (_:squash (fact v))
  : SteelT unit (pts_to r q v)
                (fun _ -> pts_to r q v `star` pure (witnessed r fact))
  = let h = get_witness #_ #(pts_to_body r q v) () in
    extract_pure r v h;
    assert (forall h'. compatible pcm_history h h' ==> lift_fact fact h');
    lift_fact_is_stable #a #p fact;
    SB.h_assert (M.pts_to r h `star` pure (Current? h /\
                                           hval h == v /\
                                           hperm h == q));

    frame_witness r (lift_fact fact) h () _;
    SB.h_assert (pts_to_body r q v h `star` pure (witnessed r fact));
    SB.frame (fun _ -> SB.intro_h_exists_erased h (pts_to_body r q v)) _

let weaken_pure (f:slprop) (p:prop) (q:prop{p ==> q})
  : SteelT unit (f `star` pure p) (fun _ -> f `star` pure q)
  = SB.h_admit _ _

let recall (#a:Type u#1) (#q:perm) (#p:Preorder.preorder a) (#fact:property a)
           (r:ref a p) (v:(Ghost.erased a))
  : SteelT unit (pts_to r q v `star` pure (witnessed r fact))
                (fun _ -> pts_to r q v `star` pure (fact v))
  = let h = SB.frame (get_witness #_ #(pts_to_body r q v)) (pure (witnessed r fact)) in
    SB.frame (fun _ -> extract_pure r v h) _;
    assert ((Current?h /\ hval h == v /\ hperm h == q));
    rearrange_pqr_prq _ _ _;
    let h1 = SB.frame (fun _ -> Steel.PCM.Effect.recall r h) _ in
    assert (compatible pcm_history h h1);
    assert (hval h == hval h1);
    assert (hval h == v);
    rearrange_pqr_prq _ _ _;
    SB.h_assert (pts_to_body r q v h `star` pure (lift_fact fact h1));
    SB.frame (fun _ -> SB.intro_h_exists_erased h (pts_to_body r q v)) _;
    SB.h_assert (pts_to r q v `star` pure (lift_fact fact h1));
    assert (lift_fact fact h1 ==> fact v);
    weaken_pure _ _ _