module TinyFStarNew

open Classical
open FunctionalExtensionality

type var = nat
type loc = nat

type heap = loc -> Tot int

type econst =
  | EcUnit
  | EcInt : i:int -> econst
  | EcLoc : l:loc -> econst
  | EcBang
  | EcAssign
  | EcSel
  | EcUpd
  | EcHeap : h:heap -> econst

type eff =
  | EfPure
  | EfAll

type tconst =
  | TcUnit
  | TcInt
  | TcRefInt
  | TcHeap

  | TcFalse
  | TcAnd

  | TcForallE
  | TcForallT : k:knd -> tconst

  | TcEqE
  | TcEqT     : k:knd -> tconst

  | TcPrecedes

and knd =
  | KType : knd
  | KKArr : karg:knd -> kres:knd -> knd
  | KTArr : targ:typ -> kres:knd -> knd

and typ =
  | TVar   : a:var -> typ
  | TConst : c:tconst -> typ

  | TArr  : t:typ -> c:cmp -> typ
  | TTLam : k:knd -> tbody:typ -> typ
  | TELam : t:typ -> ebody:typ -> typ
  | TTApp : t1:typ -> t2:typ -> typ
  | TEApp : t:typ -> e:exp -> typ

and exp =
  | EVar : x:var -> exp
  | EConst : c:econst -> exp
  | ELam : t:typ -> ebody:exp -> exp
  | EFix : d:(option exp) -> t:typ -> ebody:exp -> exp
  | EIf0 : eguard:exp -> ethen:exp -> eelse:exp -> exp
  | EApp : e1:exp -> e2:exp -> exp

and cmp =
  | Cmp :  m:eff -> t:typ -> wp:typ -> cmp

(****************************)
(* Sugar                    *)
(****************************)

let eunit = EConst EcUnit
let eint x = EConst (EcInt x)
let eloc l = EConst (EcLoc l)
let ebang el = EApp (EConst EcBang) el
let eassign el ei = EApp (EApp (EConst EcAssign) el) ei
let esel eh el = EApp (EApp (EConst EcSel) eh) el
let eupd eh el ei = EApp (EApp (EApp (EConst EcUpd) eh) el) ei
let eheap h = EConst (EcHeap h)

let tunit = TConst TcUnit
let tint = TConst TcInt
let tref = TConst TcRefInt
let theap = TConst TcHeap

let tfalse = TConst TcFalse
let tand  a b = TTApp (TTApp (TConst TcAnd) a) b

let tforalle t p = TTApp (TTApp (TConst TcForallE) t) (TELam t p)
let tforallt k p = TTApp (TConst (TcForallT k)) (TTLam k p)

let teqe e1 e2 = TEApp (TEApp (TConst TcEqE) e1) e2
let teqt k t1 t2 = TTApp (TTApp (TConst (TcForallT k)) t1) t2
let teqtype = teqt KType

let tprecedes e1 e2 = TEApp (TEApp (TConst TcPrecedes) e1) e2

(*TODO:write a function {e|t|k}shift_up which
shift both expression and type variables
and prove some properties on it*)

(****************************)
(* Expression Substitutions *)
(****************************)

(* CH: My impression is that pairing up substitutions and having a
       single set of operations for substituting would be better.
       We can return to this later though. *)

type esub = var -> Tot exp

opaque type erenaming (s:esub) = (forall (x:var). is_EVar (s x))

val is_erenaming : s:esub -> Tot (n:int{(  erenaming s  ==> n=0) /\
                                        (~(erenaming s) ==> n=1)})
let is_erenaming s = (if excluded_middle (erenaming s) then 0 else 1)

val esub_id : esub 
let esub_id = fun x -> EVar x

val esub_inc_above : nat -> var -> Tot exp
let esub_inc_above x y = if y<x then EVar y else EVar (y+1)

val esub_inc : var -> Tot exp
let esub_inc = esub_inc_above 0

let is_evar (e:exp) : int = if is_EVar e then 0 else 1

val omap : ('a -> Tot 'b) -> option 'a -> Tot (option 'b)
let omap f o =
  match o with
  | Some x -> Some (f x)
  | None   -> None
(*
val eesubst : s:esub -> e:exp -> Pure exp (requires True)
      (ensures (fun e' -> erenaming s /\ is_EVar e ==> is_EVar e'))
      (decreases %[is_evar e; is_erenaming s; e])
val tesubst : s:esub -> t:typ -> Tot typ
      (decreases %[1; is_erenaming s; t])
val kesubst : s:esub -> k:knd -> Tot knd
      (decreases %[1; is_erenaming s; k])

let rec eesubst s e =
  match e with
  | EVar x -> s x
  | EConst c -> e
  | ELam t e1 ->
     let esub_lam : y:var -> Tot (e:exp{erenaming s ==> is_EVar e}) =
       fun y -> if y=0 then EVar y
                else (eesubst esub_inc (s (y - 1))) in
     ELam (tesubst s t) (eesubst esub_lam e1)
  | EFix d t ebody ->
     let esub_lam2 : y:var -> Tot(e:exp{erenaming s ==> is_EVar e}) =
       fun y -> if y <= 1 then EVar y
                else (eesubst esub_inc (eesubst esub_inc (s (y-2)))) in
     let d' = match d with
              | Some de -> Some (eesubst s de)
              | None -> None in
     (* CH: wanted to write "d' = (omap (eesubst s) d)" but that fails
            the termination check *)
     EFix d' (tesubst s t) (eesubst esub_lam2 ebody)
  | EIf0 g ethen eelse -> EIf0 (eesubst s g) (eesubst s ethen) (eesubst s eelse)
  | EApp e1 e2 -> EApp (eesubst s e1) (eesubst s e2)

and tesubst s t =
  match t with
  | TVar a -> t
  | TConst c ->
     (match c with
      | TcEqT k     -> TConst (TcEqT (kesubst s k))
      | TcForallT k -> TConst (TcForallT (kesubst s k))
      | c           -> TConst c)
  | TArr t c ->
     let esub_lam : y : var -> Tot (e:exp{erenaming s ==> is_EVar e}) =
       fun y -> if y=0 then EVar y
                else eesubst esub_inc (s (y-1)) in
     TArr (tesubst s t)
          (Cmp (Cmp.m c) (tesubst esub_lam (Cmp.t c))
               (tesubst esub_lam (Cmp.wp c)))
  | TTLam k tbody -> TTLam (kesubst s k) (tesubst s tbody)
  | TELam t tbody ->
     let esub_lam : y : var -> Tot (e:exp{erenaming s ==> is_EVar e}) =
       fun y -> (*TODO: why does fstar complain when it is written
                        «y = 0» with spaces
                  CH: can't reproduce this, what variant do you use? *)
                if y=0 then EVar y
                else (eesubst esub_inc (s (y-1))) in
     TELam (tesubst s t) (tesubst esub_lam tbody)
  | TTApp t1 t2 -> TTApp (tesubst s t1) (tesubst s t2)
  | TEApp t e -> TEApp (tesubst s t) (eesubst s e)

and kesubst s k = match k with
  | KType -> KType
  | KKArr k kbody -> KKArr (kesubst s k) (kesubst s kbody)
  | KTArr t kbody ->
     let esub_lam : y :var -> Tot(e:exp{erenaming s ==> is_EVar e}) =
       fun y -> if y = 0 then EVar y
                else (eesubst esub_inc (s (y-1))) in
     KTArr (tesubst s t) (kesubst esub_lam kbody)

val esub_lam : s:esub -> Tot esub
let esub_lam s y =
  if y = 0 then EVar y
           else eesubst esub_inc (s (y-1))

val eesubst_extensional: s1:esub -> s2:esub{FEq s1 s2} -> e:exp ->
Lemma (requires True) (ensures (eesubst s1 e = eesubst s2 e))
                       [SMTPat (eesubst s1 e);  SMTPat (eesubst s2 e)]
let eesubst_extensional s1 s2 e = ()

val tesubst_extensional: s1:esub -> s2:esub{FEq s1 s2} -> t:typ ->
Lemma (requires True) (ensures (tesubst s1 t = tesubst s2 t))
                       [SMTPat (tesubst s1 t);  SMTPat (tesubst s2 t)]
let tesubst_extensional s1 s2 t = ()

val kesubst_extensional: s1:esub -> s2:esub{FEq s1 s2} -> k:knd ->
Lemma (requires True) (ensures (kesubst s1 k = kesubst s2 k))
let kesubst_extensional s1 s2 k = ()

val eesub_lam_hoist : t:typ -> e:exp -> s:esub -> Lemma (requires True)
      (ensures (eesubst s (ELam t e) =
                ELam (tesubst s t) (eesubst (esub_lam s) e)))
let eesub_lam_hoist t e s = ()

val tesubst_elam_hoist : t:typ -> tbody:typ -> s:esub -> Lemma (requires True)
      (ensures (tesubst s (TELam t tbody) =
                TELam (tesubst s t) (tesubst (esub_lam s) tbody)))
let tesubst_elam_hoist t tbody s = ()
*)
(*
assume val teappears_in : var -> typ -> Tot bool
*)
(****************************)
(*   Type   Substitutions   *)
(****************************)

type tsub = var -> Tot typ
opaque type trenaming (s:tsub) = (forall (x:var). is_TVar (s x))

val is_trenaming : s:tsub -> Tot (n:int{(  trenaming s  ==> n=0) /\
                                        (~(trenaming s) ==> n=1)})
let is_trenaming s = (if excluded_middle (trenaming s) then 0 else 1)

val tsub_inc_above : nat -> var -> Tot typ
let tsub_inc_above x y = if y<x then TVar y else TVar (y+1)

val tsub_id :tsub
let tsub_id = fun x -> TVar x

val tsub_inc : var -> Tot typ
let tsub_inc = tsub_inc_above 0

let is_tvar (t:typ) : int = if is_TVar t then 0 else 1
(*
val etsubst : s:tsub -> e:exp -> Tot exp
      (decreases %[1; is_trenaming s; e])
val ttsubst : s:tsub -> t:typ -> Pure typ (requires True)
      (ensures (fun t' -> trenaming s /\ is_TVar t ==> is_TVar t'))
      (decreases %[is_tvar t; is_trenaming s; t])
val ktsubst : s:tsub -> k:knd -> Tot knd
      (decreases %[1; is_trenaming s; k])

let rec etsubst s e =
  match e with
  | EVar _
  | EConst _ -> e
  | ELam t ebody -> ELam (ttsubst s t) (etsubst s ebody)
  | EFix d t ebody ->
     let d' = match d with
              | Some de -> Some (etsubst s de)
              | None -> None in
     EFix d' (ttsubst s t) (etsubst s ebody)
  | EIf0 g ethen eelse -> EIf0 (etsubst s g) (etsubst s ethen) (etsubst s eelse)
  | EApp e1 e2 -> EApp (etsubst s e1) (etsubst s e2)

and ttsubst s t =
  match t with
  | TVar a -> s a
  | TConst c ->
     (match c with
      | TcEqT k -> TConst (TcEqT (ktsubst s k))
      | TcForallT k -> TConst (TcForallT (ktsubst s k))
      | c -> TConst c)
  | TArr t c ->
     TArr (ttsubst s t)
          (Cmp (Cmp.m c) (ttsubst s (Cmp.t c)) (ttsubst s (Cmp.wp c)))
  | TTLam k tbody ->
     let tsub_lam : y : var -> Tot (t:typ{trenaming s ==> is_TVar t}) =
       fun y -> if y=0 then TVar y
                else (ttsubst tsub_inc (s (y-1))) in
     TTLam (ktsubst s k) (ttsubst tsub_lam tbody)
  | TELam t tbody -> TELam (ttsubst s t) (ttsubst s tbody)
  | TTApp t1 t2 -> TTApp (ttsubst s t1) (ttsubst s t2)
  | TEApp t e -> TEApp (ttsubst s t) (etsubst s e)

and ktsubst s k =
  match k with
  | KType -> KType
  | KKArr k kbody ->
     let tsub_lam : y :var -> Tot(t:typ{trenaming s ==> is_TVar t}) =
       fun y -> if y = 0 then TVar y
                else (ttsubst tsub_inc (s (y-1))) in
     KKArr (ktsubst s k) (ktsubst tsub_lam kbody)
  | KTArr t kbody ->
     KTArr (ttsubst s t) (ktsubst s kbody)
val tsub_lam: s:tsub -> Tot tsub
let tsub_lam s y =
  if y = 0 then TVar y
           else ttsubst tsub_inc (s (y-1))
val etsubst_extensional: s1:tsub -> s2:tsub{FEq s1 s2} -> e:exp ->
Lemma (requires True) (ensures (etsubst s1 e = etsubst s2 e))
                       [SMTPat (etsubst s1 e);  SMTPat (etsubst s2 e)]
let etsubst_extensional s1 s2 e = ()

val ttsubst_extensional: s1:tsub -> s2:tsub{FEq s1 s2} -> t:typ ->
Lemma (requires True) (ensures (ttsubst s1 t = ttsubst s2 t))
                       [SMTPat (ttsubst s1 t);  SMTPat (ttsubst s2 t)]
let ttsubst_extensional s1 s2 t = ()

val ktsubst_extensional: s1:tsub -> s2:tsub{FEq s1 s2} -> k:knd ->
Lemma (requires True) (ensures (ktsubst s1 k = ktsubst s2 k))
let ktsubst_extensional s1 s2 k = ()

val ttsubst_tlam_hoist : k:knd -> tbody:typ -> s:tsub -> Lemma (requires True)
      (ensures (ttsubst s (TTLam k tbody) =
                TTLam (ktsubst s k) (ttsubst (tsub_lam s) tbody)))

let ttsubst_tlam_hoist t e s = ()
*)

(********************************)
(* Global substitution function *)
(********************************)

(*The projectors for pairs were not working well with substitutions*)
type sub = 
| Sub : es:esub -> ts:tsub -> sub

opaque type renaming (s:sub) = (erenaming (Sub.es s))  /\ (trenaming (Sub.ts s))

val is_renaming : s:sub -> Tot (n:int{(  renaming s  ==> n=0) /\
                                       (~(renaming s) ==> n=1)})
let is_renaming s = (if excluded_middle (renaming s) then 0 else 1)

let sub_einc = Sub esub_inc tsub_id
let sub_tinc s = Sub esub_id tsub_inc

val esubst : s:sub -> e:exp -> Pure exp (requires True)
      (ensures (fun e' -> renaming s /\ is_EVar e ==> is_EVar e'))
      (decreases %[is_evar e; is_renaming s;1; e])
val tsubst : s:sub -> t:typ -> Pure typ (requires True)
      (ensures (fun t' -> renaming s /\ is_TVar t ==> is_TVar t'))
      (decreases %[is_tvar t; is_renaming s;1; t])
val csubst : s:sub -> c:cmp -> Tot cmp
      (decreases %[1; is_renaming s; 1; c])
val ksubst : s:sub -> k:knd -> Tot knd
      (decreases %[1; is_renaming s; 1; k])
val esub_elam: s:sub -> x:var -> Tot(e:exp{renaming s ==> is_EVar e})
      (decreases %[1; is_renaming s; 0; EVar 0])
val tsub_elam : s:sub -> a:var -> Tot(t:typ{renaming s ==> is_TVar t}) 
      (decreases %[1; is_renaming s; 0; TVar 0])
val esub_tlam: s:sub -> x:var -> Tot(e:exp{renaming s ==> is_EVar e})
      (decreases %[1; is_renaming s; 0; EVar 0])
val tsub_tlam : s:sub -> a:var -> Tot(t:typ{renaming s ==> is_TVar t}) 
      (decreases %[1; is_renaming s; 0; TVar 0])
val esub_elam2: s:sub -> x:var -> Tot(e:exp{renaming s ==> is_EVar e})
      (decreases %[1; is_renaming s; 0; EVar 0])
val tsub_elam2 : s:sub -> a:var -> Tot(t:typ{renaming s ==> is_TVar t}) 
      (decreases %[1; is_renaming s; 0; TVar 0])

let rec esub_elam s =
fun x -> if x = 0 then EVar x
         else esubst (Sub esub_inc tsub_id) (Sub.es s (x-1)) 

and tsub_elam s =
fun a -> tsubst (Sub esub_inc tsub_id) (Sub.ts s a) 

and esub_tlam s =
fun x -> esubst (Sub esub_id tsub_inc) (Sub.es s x)

and tsub_tlam s =
fun a -> if a = 0 then TVar a
         else tsubst (Sub esub_id tsub_inc) (Sub.ts s a)

and esub_elam2 s =
fun x -> if x <= 1 then EVar x
                   else (esubst (Sub esub_inc tsub_id) (esubst (Sub esub_inc tsub_id) (Sub.es s (x-2))))

and tsub_elam2 s =
fun a -> tsubst (Sub esub_inc tsub_id) (tsubst (Sub esub_inc tsub_id) (Sub.ts s a))

(*Substitution inside expressions*)
and esubst s e =
  match e with
  | EVar x -> Sub.es s x
  | EConst _ -> e
  | ELam t ebody -> 
let sub_elam = Sub (esub_elam s) (tsub_elam s) in
ELam (tsubst s t) (esubst sub_elam ebody)
  | EFix d t ebody -> 
let sub_lam2 = Sub (esub_elam2 s) (tsub_elam2 s) in
     let d' = match d with
              | Some de -> Some (esubst s de)
              | None -> None in
     (* CH: wanted to write "d' = (omap (eesubst s) d)" but that fails
            the termination check *)
     (EFix d' (tsubst s t) (esubst sub_lam2 ebody))
  | EIf0 g ethen eelse -> EIf0 (esubst s g) (esubst s ethen) (esubst s eelse)
  | EApp e1 e2 -> EApp (esubst s e1) (esubst s e2)

(*Substitution inside types*)
and tsubst s t =
  match t with
  | TVar a -> (Sub.ts s a)
  | TConst c ->
     (match c with
      | TcEqT k -> TConst (TcEqT (ksubst s k))
      | TcForallT k -> TConst (TcForallT (ksubst s k))
      | c -> TConst c)
  | TArr t c -> 
let sub_elam = Sub (esub_elam s) (tsub_elam s) in
     TArr (tsubst s t)
          (csubst sub_elam c)
  | TTLam k tbody -> 
let sub_tlam = Sub (esub_tlam s) (tsub_tlam s) in
     TTLam (ksubst s k) (tsubst sub_tlam tbody)
  | TELam t tbody -> 
let sub_elam = Sub (esub_elam s) (tsub_elam s) in
     TELam (tsubst s t) (tsubst sub_elam tbody)
  | TTApp t1 t2 -> TTApp (tsubst s t1) (tsubst s t2)
  | TEApp t e -> TEApp (tsubst s t) (esubst s e)
and csubst s c = let Cmp m t wp = c in
Cmp m (tsubst s t) (tsubst s wp)
(*Substitution inside kinds*)
and ksubst s k =
  match k with
  | KType -> KType
  | KKArr k kbody -> 
let sub_tlam = Sub (esub_tlam s) (tsub_tlam s) in
     KKArr (ksubst s k) (ksubst sub_tlam kbody)
  | KTArr t kbody -> 
let sub_elam = Sub (esub_elam s) (tsub_elam s) in
     (KTArr (tsubst s t) (ksubst sub_elam kbody))



val sub_elam : s:sub -> Tot sub
let sub_elam s = Sub (esub_elam s) (tsub_elam s)

val esub_elam_at0 : s:sub -> Lemma (Sub.es (sub_elam s) 0 = EVar 0)
let esub_elam_at0 s = ()

val sub_tlam : s:sub -> Tot sub
let sub_tlam s = Sub (esub_tlam s) (tsub_tlam s)



val etsubst : s:tsub -> e:exp -> Tot exp
let etsubst s e = esubst (Sub esub_id s) e

val ttsubst : s:tsub -> t:typ -> Tot typ
let ttsubst s t = tsubst (Sub esub_id s) t

val ktsubst : s:tsub -> k:knd -> Tot knd
let ktsubst s k = ksubst (Sub esub_id s) k

val eesubst : s:esub -> e:exp -> Tot exp
val tesubst : s:esub -> t:typ -> Tot typ
val kesubst : s:esub -> k:knd -> Tot knd

let eesubst s e = esubst (Sub s tsub_id) e

let tesubst s t = tsubst (Sub s tsub_id) t

let kesubst s k = ksubst (Sub s tsub_id) k

(* Beta substitution for expressions *)

val esub_beta_gen : var -> exp -> Tot esub
let esub_beta_gen x e = fun y -> if y < x then (EVar y)
                                 else if y = x then e
                                 else (EVar (y-1))

val eesubst_beta_gen : var -> exp -> exp -> Tot exp
let eesubst_beta_gen x e' = eesubst (esub_beta_gen x e')

let eesubst_beta = eesubst_beta_gen 0

val tesubst_beta_gen : var -> exp -> typ -> Tot typ
let tesubst_beta_gen x e = tesubst (esub_beta_gen x e)

let tesubst_beta = tesubst_beta_gen 0

val kesubst_beta_gen : var -> exp -> knd -> Tot knd
let kesubst_beta_gen x e = kesubst (esub_beta_gen x e)

let kesubst_beta = kesubst_beta_gen 0

let eesh = eesubst esub_inc
let tesh = tesubst esub_inc
let kesh = kesubst esub_inc

(* Beta substitution for types *)
val tsub_beta_gen : var -> typ -> Tot tsub
let tsub_beta_gen x t = fun y -> if y < x then (TVar y)
                                 else if y = x then t
                                 else (TVar (y-1))

val ttsubst_beta_gen : var -> typ -> typ -> Tot typ
let ttsubst_beta_gen x t' = ttsubst (tsub_beta_gen x t')

val ktsubst_beta_gen : var -> typ -> knd -> Tot knd
let ktsubst_beta_gen x t' = ktsubst (tsub_beta_gen x t')

let ttsubst_beta = ttsubst_beta_gen 0

let ktsubst_beta = ktsubst_beta_gen 0

let etsh = etsubst tsub_inc
let ttsh = ttsubst tsub_inc
let ktsh = ktsubst tsub_inc

(********************************)
(* Composition of substitutions *)
(********************************)

val sub_comp : s1:sub -> s2:sub -> Tot sub
let sub_comp s1 s2 =
Sub (fun x -> esubst s1 (Sub.es s2 x)) (fun a -> tsubst s1 (Sub.ts s2 a))

val esubst_comp : s1:sub -> s2:sub -> e:exp -> Lemma (esubst s1 (esubst s2 e) = esubst (sub_comp s1 s2) e)
val tsubst_comp : s1:sub -> s2:sub -> t:typ -> Lemma (tsubst s1 (tsubst s2 t) = tsubst (sub_comp s1 s2) t)
val ksubst_comp : s1:sub -> s2:sub -> k:knd -> Lemma (ksubst s1 (ksubst s2 k) = ksubst (sub_comp s1 s2) k)

let esubst_comp s1 s2 e = admit()
let tsubst_comp s1 s2 t = admit()
let ksubst_comp s1 s2 k = admit()

(****************************)
(* Derived logic constants  *)
(****************************)

let timpl t1 t2 = tforalle t1 (tesh t2)
let tnot t = timpl t tfalse
let ttrue = tnot tfalse
let tor t1 t2 = timpl (tnot t1) t2

(*************************************)
(*   Common substitution functions   *)
(*************************************)
(*TODO:Settle down the substitution strategy*)
(*
val eshift_up_above : ei:nat -> ti:nat ->
                      eplus:nat -> tplus:nat ->
                      e:exp -> Tot exp
val tshift_up_above : ei:nat -> ti:nat ->
                      eplus:nat -> tplus:nat ->
                      t:typ -> Tot typ
val kshift_up_above : ei:nat -> ti:nat ->
                      eplus:nat -> tplus:nat ->
                      t:typ -> Tot typ
*)

(***********************)
(*  Heap manipulation  *)
(***********************)

val upd_heap : l:loc -> i:int -> h:heap -> Tot heap
let upd_heap l i h =
  fun x -> if x = l then i else h x

(********************************************)
(* Reduction for types and pure expressions *)
(********************************************)

val is_value : exp -> Tot bool
let rec is_value e =
  match e with
  | EConst _
  | ELam _ _
  | EVar _
  | EFix _ _ _ -> true
  | EIf0 _ _ _ -> false
  | EApp e1 e2 -> is_value e2 &&
      (match e1 with
       | EApp e11 e12 -> is_value e12 &&
         (match e11 with
          | EApp (EConst c) e112 -> is_EcUpd c && is_value e112
          | EConst c             -> is_EcUpd c || is_EcSel c
          | _ -> false)
       | EConst c -> is_EcUpd c || is_EcSel c || is_EcAssign c || is_EcHeap c
       | _ -> false)

type value = e:exp{is_value e}

type tstep : typ -> typ -> Type =
  | TsEBeta : tx:typ ->
              t:typ ->
              e:exp ->
              tstep (TEApp (TELam tx t) e) (tesubst_beta e t)
  | TsTBeta : k:knd ->
              t:typ ->
              t':typ ->
              tstep (TTApp (TTLam k t) t') (ttsubst_beta t' t)
  | TsArrT1 : #t1:typ->
              #t1':typ->
              c:cmp ->
              =ht:tstep t1 t1' ->
              tstep (TArr t1 c) (TArr t1' c)
  | TsTAppT1 : #t1:typ ->
               #t1':typ ->
               t2 : typ ->
               =ht:tstep t1 t1' ->
               tstep (TTApp t1 t2) (TTApp t1' t2)
  | TsTAppT2 : t1:typ ->
               #t2:typ ->
               #t2':typ ->
               =ht:tstep t2 t2' ->
               tstep (TTApp t1 t2) (TTApp t1 t2')
  | TsEAppT : #t:typ ->
              #t':typ ->
              e:exp ->
              =ht:tstep t t' ->
              tstep (TEApp t e) (TEApp t' e)
  | TsEAppE : t:typ ->
              #e:exp ->
              #e':exp ->
              =he:epstep e e' ->
              tstep (TEApp t e) (TEApp t e')
  | TsTLamT : k:knd ->
              #t:typ ->
              #t':typ ->
              =ht:tstep t t' ->
              tstep (TTLam k t) (TTLam k t')
  | TsELamT1 : #t1:typ ->
               #t1':typ ->
               t2:typ ->
               =ht:tstep t1 t1' ->
               tstep (TELam t1 t2) (TELam t1' t2)
(*Why do the last two rules reduce different part of the term ?
  Why do we have TTLam k t ~> TTLam k t' and not TELam t1 t2 ~> TELam t1 t2' ? *)
and epstep : exp -> exp -> Type =
  | PsBeta :  t:typ ->
              ebody:exp ->
              v:value ->
              epstep (EApp (ELam t ebody) v) (eesubst_beta v ebody)
  | PsFix : d:option exp ->
            t:typ ->
            ebody:exp ->
            v:value ->
            epstep (EApp (EFix d t ebody) v) (eesubst_beta (EFix d t ebody)
                                                (eesubst_beta v ebody))
  | PsIf0 :  e1:exp ->
             e2:exp ->
             epstep (EIf0 (eint 0) e1 e2) e1
  | PsIfS :  i:int{i<>0} ->
             e1:exp ->
             e2:exp ->
             epstep (EIf0 (eint i) e1 e2) e2
  | PsAppE1 : #e1:exp ->
              #e1':exp ->
              e2:exp ->
              =ht:epstep e1 e1' ->
              epstep (EApp e1 e2) (EApp e1' e2)
  | PsAppE2 : e1:exp ->
              #e2:exp ->
              #e2':exp ->
              =ht:epstep e2 e2' ->
              epstep (EApp e1 e2) (EApp e1 e2')
  | PsLamT : #t:typ ->
             #t':typ ->
             ebody:exp ->
             =ht:tstep t t' ->
             epstep (ELam t ebody) (ELam t' ebody)
  | PsFixT : d:option exp ->
             #t:typ ->
             #t':typ ->
             ebody:exp ->
             #ht:tstep t t' ->
             epstep (EFix d t ebody) (EFix d t' ebody)
  | PsFixD : #de:exp ->
             #de':exp ->
             t:typ ->
             ebody:exp ->
             =ht:epstep de de' ->
             epstep (EFix (Some de) t ebody) (EFix (Some de') t ebody)
  | PsIf0E0 : #e0:exp ->
              #e0':exp ->
              ethen:exp ->
              eelse:exp ->
              =ht:epstep e0 e0' ->
              epstep (EIf0 e0 ethen eelse) (EIf0 e0' ethen eelse)

type cfg =
  | Cfg : h:heap -> e:exp -> cfg

type eistep : cfg -> cfg -> Type =
  | IsRd :  h:heap ->
            l:loc ->
            eistep (Cfg h (ebang (eloc l))) (Cfg h (eint (h l)))
  | IsWr :  h:heap ->
            l:loc ->
            i:int ->
            eistep (Cfg h (eassign (eloc l) (eint i)))
                   (Cfg (upd_heap l i h) eunit)
  | IsBeta :  h:heap ->
              t:typ ->
              ebody:exp ->
              v:value ->
              eistep (Cfg h (EApp (ELam t ebody) v))
                     (Cfg h (eesubst_beta v ebody))
  | IsFix : h:heap ->
            d:option exp ->
            t:typ ->
            ebody:exp ->
            v:value ->
            eistep (Cfg h (EApp (EFix d t ebody) v))
                   (Cfg h (eesubst_beta (EFix d t ebody)
                                        (eesubst_beta v ebody)))
  | IsIf0 :  h:heap ->
             e1:exp ->
             e2:exp ->
             eistep (Cfg h (EIf0 (eint 0) e1 e2)) (Cfg h e1)
  | IsIfS :  h:heap ->
             i:int{i<>0} ->
             e1:exp ->
             e2:exp ->
             eistep (Cfg h (EIf0 (eint i) e1 e2)) (Cfg h e2)
  | IsAppE1 : h:heap ->
              #e1:exp ->
              #e1':exp ->
              e2:exp ->
              =ht:epstep e1 e1' ->
              eistep (Cfg h (EApp e1 e2)) (Cfg h (EApp e1' e2))
  | IsAppE2 : h:heap ->
              e1:exp ->
              #e2:exp ->
              #e2':exp ->
              =ht:epstep e2 e2' ->
              eistep (Cfg h (EApp e1 e2)) (Cfg h (EApp e1 e2'))
  | IsIf0E0 : h:heap ->
              #e0:exp ->
              #e0':exp ->
              ethen:exp ->
              eelse:exp ->
              =ht:epstep e0 e0' ->
              eistep (Cfg h (EIf0 e0 ethen eelse))
                     (Cfg h (EIf0 e0' ethen eelse))

(********************************************************)
(* The signatures of Pure and ST and other Monad ops    *)
(********************************************************)
let k_pre_pure    = KType
let k_pre_all     = KTArr theap KType

let k_post_pure t = KTArr t KType
let k_post_all  t = KTArr t (KTArr theap KType)

let k_pure t      = KKArr (k_post_pure t) k_pre_pure
let k_all  t      = KKArr (k_post_all  t) k_pre_all

let k_m m = match m with
| EfPure -> k_pure
| EfAll  -> k_all

let tot t = Cmp EfPure t (TTLam (k_post_pure t)
                           (tforalle (ttsh t) (TEApp (TVar 1) (EVar 0))))

val return_pure : t:typ -> e:exp -> Tot typ
let return_pure t e = TTLam (k_post_pure t) (TEApp (TVar 0) e)

val return_all : t:typ -> e:exp -> Tot typ
let return_all t e = TTLam (k_post_all t) (TELam theap
                    (TEApp (TEApp (TVar 0) (eesh (etsh e))) (EVar 0)))

(*TODO: do not forget to shift up e !!!*)
(*Actually, can it have free variables ?*)
val bind_pure:  ta : typ -> tb : typ
             -> wp : typ
             -> f  : typ
             -> Tot typ
let bind_pure ta tb wp f =
   TTLam (k_post_pure tb) (*p*)
     (TTApp (ttsh wp)
        (TELam (*shift*)(ttsh tb)(*x*)
           (TTApp (TEApp (ttsh (tesh f)) (EVar 0)) (TVar 0))))

val bind_all:  ta:typ -> tb:typ
             ->wp : typ
             ->f  : typ
             ->Tot typ
let bind_all ta tb wp f =
  (TTLam (k_post_all tb) (*p*)
     (TTApp (ttsh wp)
        (TELam (ttsh tb) (*x*)
           (TELam theap
              (TEApp (TTApp (TEApp (ttsh (tesh (tesh f))) (EVar 1))
                            (TVar 0))
                     (EVar 0))))))

val monotonic_pure : a:typ -> wp:typ -> Tot typ
let monotonic_pure a wp =
  tforallt (k_post_pure a)
    (tforallt (k_post_pure (ttsh a))
        (timpl
          ((*forall x. p1 x ==> p2 x *)
            tforalle (ttsh (ttsh a))
               (timpl  (TEApp (TVar 1 (*p1*)) (EVar 0))
                       (TEApp (TVar 0 (*p2*)) (EVar 0))
               )
          )
          ((*wp p1 ==> wp p2*)
            timpl (TTApp (ttsh (ttsh wp)) (TVar 1))
                  (TTApp (ttsh (ttsh wp)) (TVar 0))
          )
        )
     )

val monotonic_all : a:typ -> wp:typ -> Tot typ
let monotonic_all a wp =
  tforallt (k_post_pure a)
    (tforallt (k_post_pure (ttsh a))
        (
          timpl
          ((*forall x. p1 x ==> p2 x *)
            tforalle (ttsh (ttsh a))
               (tforalle theap
                    (timpl  (TEApp (TEApp (TVar 1 (*p1*)) (EVar 1(*x*))) (EVar 0) )
                            (TEApp (TEApp (TVar 0 (*p2*)) (EVar 1)) (EVar 0))
                    )
               )
          )
          ((*wp p1 ==> wp p2*)
            tforalle theap
              (timpl (TEApp (TTApp (ttsh (ttsh wp)) (TVar 1)) (EVar 0))
                     (TEApp (TTApp (ttsh (ttsh wp)) (TVar 0)) (EVar 0))
              )
          )
        )
    )

let monotonic m = match m with
  | EfPure -> monotonic_pure
  | EfAll  -> monotonic_all

val op_pure : a:typ -> op:(typ -> typ -> Tot typ) ->
              wp1:typ -> wp2:typ -> Tot typ
let op_pure a op wp1 wp2 =
  TTLam (k_post_pure a) (op (TTApp (ttsh wp1) (TVar 0))
                            (TTApp (ttsh wp2) (TVar 0)))

val op_all : a:typ -> op:(typ -> typ -> Tot typ) ->
             wp1:typ -> wp2:typ -> Tot typ
let op_all a op wp1 wp2 =
  TTLam (k_post_all a)
    (TELam theap (op (TEApp (TTApp (tesh (ttsh wp1)) (TVar 0)) (EVar 0))
                     (TEApp (TTApp (tesh (ttsh wp2)) (TVar 0)) (EVar 0))))

let op m =
  match m with
  | EfPure -> op_pure
  | EfAll  -> op_all

val up_pure : a:typ -> t:typ -> Tot typ
let up_pure a t =
  TTLam (k_post_pure a) (ttsh t)

val up_all : a:typ -> t:typ -> Tot typ
let up_all a t =
  TTLam (k_post_pure a) (TELam theap (tesh (ttsh t)))

let up m =
  match m with
  | EfPure -> up_pure
  | EfAll  -> up_all

val down_pure : a:typ -> wp:typ -> Tot typ
let down_pure a wp =
  tforallt (k_post_pure a) (TTApp (ttsh wp) (TVar 0))

val down_all : a : typ -> wp:typ -> Tot typ
let down_all a wp =
  tforallt (k_post_all a)
     (tforalle theap
         (TEApp (TTApp (tesh (ttsh wp)) (TVar 0)) (EVar 0)))

let down m =
  match m with
  | EfPure -> down_pure
  | EfAll  -> down_all

val closee_pure : a:typ -> b:typ -> f:typ -> Tot typ
let closee_pure a b f =
  TTLam (k_post_pure a) (*p*)
  (tforalle (ttsh b)
    (TTApp (TEApp (tesh (ttsh f)) (EVar 0)) (TVar 0)))

val closee_all : a:typ -> b:typ -> f:typ -> Tot typ
let closee_all a b f =
  TTLam (k_post_all a) (*p*)
  (TELam theap (
    (tforalle (tesh (ttsh b))
      (TEApp (TTApp (TEApp (tesh (tesh (ttsh f))) (EVar 0)) (TVar 0))
             (EVar 1)))))

val closet_pure : a:typ -> f:typ -> Tot typ
let closet_pure a f =
  TTLam (k_post_pure a)
  (tforallt KType
    (TTApp (TTApp (ttsh (ttsh f)) (TVar 0)) (TVar 1)))

val closet_all : a:typ -> f:typ -> Tot typ
let closet_all a f =
  TTLam (k_post_all a)
  (TELam theap
    (tforallt KType
      (TEApp (TTApp (TTApp (ttsh (tesh (ttsh f))) (TVar 0)) (TVar 1)) (EVar 0))))

val ite_pure : a:typ -> wp0:typ -> wp1:typ -> wp2:typ -> Tot typ
let ite_pure a wp0 wp1 wp2 =
  bind_pure tint a wp0
  (
   TELam (tint)
    (
      op_pure (tesh a) tand
      ((*up (i=0) ==> wp1*)
       op_pure (tesh a) timpl
        (
         up_pure (tesh a)
           (teqe (EVar 0) (eint 0))
        )
         wp1
      )
      ((*up (i!=0) ==> wp2*)
       op_pure (tesh a) timpl
        (
         up_pure (tesh a)
           (tnot (teqe (EVar 0) (eint 0)))
        )
         wp2
      )
    )
  )

val ite_all : a:typ -> wp0:typ -> wp1:typ -> wp2:typ -> Tot typ
let ite_all a wp0 wp1 wp2 =
  bind_all tint a wp0
  (
   TELam (tint)
    (
      op_all (tesh a) tand
      ((*up (i=0) ==> wp1*)
       op_all (tesh a) timpl
        (
         up_all (tesh a)
           (teqe (EVar 0) (eint 0))
        )
         wp1
      )
      ((*up (i!=0) ==> wp2*)
       op_all (tesh a) timpl
        (
         up_all (tesh a)
           (tnot (teqe (EVar 0) (eint 0)))
        )
         wp2
      )
    )
  )

val ite : m:eff -> a:typ -> wp0:typ -> wp1:typ -> wp2:typ -> Tot typ
let ite m =
  match m with
  | EfPure -> ite_pure
  | EfAll  -> ite_all

val valid_pure : typ -> Tot typ
let valid_pure p = p

val valid_all : typ -> Tot typ
let valid_all p =
  tforalle (theap) (TEApp (tesh p) (EVar 0))

val lift_pure_all : a:typ -> wp:typ -> Tot typ
let lift_pure_all a wp =
  TTLam (k_post_all a)
  (
   TELam theap
   (
    TTApp (tesh (ttsh wp))
     (
      TELam (tesh (ttsh a))
       (
        TEApp (TEApp (TVar 0) (EVar 0)) (EVar 1)
       )
     )
   )
  )

val eff_sub : m1:eff -> m2:eff -> Tot bool
let eff_sub m1 m2 =
  match m1,m2 with
  | EfPure,EfPure -> true
  | EfPure,EfAll  -> true
  | EfAll,EfAll   -> true
  | EfAll,EfPure  -> false

val lift : m1:eff -> m2:eff{eff_sub m1 m2} -> a:typ -> wp:typ -> Tot typ
let lift m1 m2 =
  match m1, m2 with
  | EfPure, EfAll  -> lift_pure_all
  | EfPure, EfPure -> (fun a wp -> wp)
  | EfAll, EfAll -> (fun a wp -> wp)

val bind : m:eff -> ta:typ -> tb:typ -> wp:typ -> f:typ -> Tot typ
let bind m ta tb wp f =
  match m with
  | EfPure -> bind_pure ta tb wp f
  | EfAll  -> bind_all ta tb wp f

val tfix_wp : tx:typ -> t'':typ -> d:exp -> wp:typ -> Tot typ
let tfix_wp tx t'' d wp =
  op_pure t'' tand
          (up_pure (t'') (TEApp (TEApp (TConst TcPrecedes) (EApp d (EVar 0)))
                                (EApp d (EVar 1)))) wp

(********************************************************)
(* Signature for type and expression constants          *)
(********************************************************)

val tconsts : tconst -> Tot knd
let tconsts tc =
  match tc with
  | TcUnit
  | TcInt
  | TcRefInt
  | TcHeap
  | TcFalse     -> KType

  | TcAnd       -> KKArr KType (KKArr KType KType)

  | TcForallE   -> KKArr KType (KKArr (KTArr (TVar 0) KType) KType)

  | TcEqE       -> KKArr KType (KTArr (TVar 0) (KTArr (TVar 0) KType))

  | TcPrecedes  -> KKArr KType (KKArr KType
                                      (KTArr (TVar 0) (KTArr (TVar 1) KType)))

  | TcEqT     k -> KKArr k (KKArr (ktsh k) KType)

  | TcForallT k -> KKArr (KKArr k KType) KType

let cmp_bang x =
  Cmp EfAll tint (TTLam (k_post_all tint) (TELam theap
                   (TEApp (TEApp (TVar 1) (esel (EVar 0) x)) (EVar 0))))

let cmp_assign x y =
  Cmp EfAll tunit (TTLam (k_post_all tunit) (TELam theap
                    (TEApp (TEApp (TVar 1) eunit) (eupd (EVar 0) x y))))

val econsts : econst -> Tot typ
let econsts ec =
  match ec with
  | EcUnit   -> tunit
  | EcInt _  -> tint
  | EcLoc _  -> tref
  | EcBang   -> TArr tref (cmp_bang (EVar 0))
  | EcAssign -> TArr tref (tot (TArr tint (cmp_assign (EVar 1) (EVar 0))))
  | EcSel    -> TArr theap (tot (TArr tref (tot tint)))
  | EcUpd    -> TArr theap (tot (TArr tref (tot (TArr tint (tot theap)))))
  | EcHeap _ -> theap

(***********************)
(* Head normal forms   *)
(***********************)

(* head_eq (and head_const_eq) might seem too strong,
   but we only use their negation, which should be weak enough
   to be closed under substitution for instance. *)

val head_const : typ -> Tot (option tconst)
let rec head_const t =
  match t with
  | TConst tc  -> Some tc
  | TTApp t1 _
  | TEApp t1 _ -> head_const t1
  | _          -> None

val head_const_eq : ot1:(option tconst) -> ot2:(option tconst) -> Tot bool
let head_const_eq ot1 ot2 =
  match ot1, ot2 with
  | Some (TcForallT _), Some (TcForallT _)
  | Some (TcEqT _)    , Some (TcEqT _)     -> true
  | _                 , _                  -> ot1 = ot2

val is_hnf : typ -> Tot bool
let is_hnf t = is_TArr t || is_Some (head_const t)

val head_eq : t1:typ{is_hnf t1} -> t2:typ{is_hnf t2} -> Tot bool
let head_eq t1 t2 =
  match t1, t2 with
  | TArr _ (Cmp EfPure _ _), TArr _ (Cmp EfPure _ _)
  | TArr _ (Cmp EfAll  _ _), TArr _ (Cmp EfAll  _ _) -> true
  | _, _ -> is_Some (head_const t1) && head_const_eq (head_const t1)
                                                     (head_const t2)

(***********************)
(* Precedes on values  *)
(***********************)

val precedes : v1:value -> v2:value -> Tot bool
let precedes v1 v2 =
  match v1, v2 with
  | EConst (EcInt i1), EConst (EcInt i2) -> i1 >= 0 && i2 >= 0 && i1 < i2
  | _, _ -> false

(***********************)
(* Typing environments *)
(***********************)

type eenv = var -> Tot (option typ)
type tenv = var -> Tot (option knd)

val eempty : eenv
let eempty x = None

val tempty : tenv
let tempty x = None

type env =
| Env : e:eenv -> t:tenv -> env

let empty = Env eempty tempty

val enveshift : env -> Tot env
let enveshift e =
  let Env eenvi tenvi = e in
  let eenvi' : eenv = fun (x:var) -> omap tesh (eenvi x) in
  let tenvi' : tenv = fun (x:var) -> omap kesh (tenvi x) in
  Env eenvi' tenvi'

val envtshift : env -> Tot env
let envtshift e =
  let Env eenvi tenvi = e in
  let eenvi' : eenv = fun x -> omap ttsh (eenvi x) in
  let tenvi' : tenv = fun x -> omap ktsh (tenvi x) in
  Env eenvi' tenvi'

(* SF: Let's assume we just need to extend at 0 *)
(* SF: with this version, it was not possible to prove simple things about the env*)
(*
val eextend : typ -> env -> Tot env
let eextend t e =
  let Env eenvi tenvi = e in
  let eenvi' : eenv = fun x -> if x = 0 then Some t
                               else eenvi (x-1)
  in enveshift (Env eenvi' tenvi)
*)
val eextend : typ -> env -> Tot env
let eextend t e =
  let Env eenvi tenvi = e in
  let eenvi' : eenv = fun x -> if x = 0 then Some (tesh t)
                                        else omap tesh (eenvi (x-1)) 
  in
  let tenvi' : tenv = fun x -> omap kesh (tenvi x) in
  Env eenvi' tenvi'
(*
val textend : knd -> env -> Tot env
let textend k e =
  let Env eenvi tenvi = e in
  let tenvi' : tenv = fun x -> if x = 0 then Some k
                               else tenvi (x-1)
  in envtshift (Env eenvi tenvi')
*)
val textend : knd -> env -> Tot env
let textend k e =
  let Env eenvi tenvi = e in
  let eenvi' : eenv = fun x -> omap ttsh (eenvi x) in
  let tenvi' : tenv = fun x -> if x = 0 then Some (ktsh k)
                               else omap ktsh (tenvi (x-1))
  in (Env eenvi' tenvi')

val lookup_evar : env -> var -> Tot (option typ)
let lookup_evar g x = Env.e g x

val lookup_tvar : env -> var -> Tot (option knd)
let lookup_tvar g x = Env.t g x

val plouf : t1:typ -> Tot unit
let plouf t1= assert(is_Some (lookup_evar (eextend tfalse empty) 0) )
(**************)
(*   Typing   *)
(**************)

type typing : env -> exp -> cmp -> Type =

| TyVar : #g:env -> x:var{is_Some (lookup_evar g x)} ->
          =h:ewf g ->
              typing g (EVar x) (tot (Some.v (lookup_evar g x)))

| TyConst : g:env -> c:econst ->
           =h:ewf g ->
              typing g (EConst c) (tot (econsts c))

| TyAbs : #g:env ->
          #t1:typ ->
          #ebody:exp ->
          m:eff ->
          t2:typ ->
          wp:typ ->
          =hk:kinding g t1 KType ->
           typing (eextend t1 g) ebody (Cmp m t2 wp) ->
           typing g (ELam t1 ebody) (tot (TArr t1 (Cmp m t2 wp)))
(*
    G |- t : Type
    G |- d : Tot (x:tx -> Tot t')
    t = y:tx -> PURE t'' wp
    G, x:tx, f: (y:tx -> PURE t'' (up_PURE (d y << d x) /\_PURE wp))
       |- e : (PURE t'' wp[x/y])
    ---------------------------------------------------------------- [T-Fix]
    G |- let rec (f^d:t) x = e : Tot t


    G |- t : Type
    t = y:tx -> ALL t' wp
    G, x:tx, f:t |- e : (ALL t' wp[x/y])
    ------------------------------------ [T-FixOmega]
    G |- let rec (f:t) x = e : Tot t
*)
(*TODO: check and finish this rule. Do not use it like that !!!*)
| TyFix : #g:env -> #tx:typ -> #t':typ -> #d:exp -> #t'':typ -> #wp:typ -> #ebody:exp ->
          kinding g (TArr tx (Cmp EfPure t'' wp)) KType ->
          typing g d (tot (TArr tx (tot t'))) ->
          typing (eextend
                    (tesh (TArr tx (Cmp EfPure t'' (tfix_wp tx t'' d wp))))
                    (eextend tx g))
                 ebody (Cmp EfPure (tesh t'') (tesh wp)) ->
          typing g (EFix (Some d) (TArr tx (Cmp EfPure t'' wp)) ebody)
                 (tot (TArr tx (Cmp EfPure t'' wp)))

| TyFixOmega : g:env -> tx:typ -> t':typ -> wp:typ -> ebody : exp ->
              kinding g (TArr tx (Cmp EfAll t' wp)) KType ->
              typing (eextend (tesh (TArr tx (Cmp EfAll t' wp))) (eextend tx g))
                     ebody (Cmp EfAll (tesh t') (tesh wp)) ->
              typing g (EFix None (TArr tx (Cmp EfAll t' wp)) ebody)
                     (tot (TArr tx (Cmp EfAll t' wp) ))
(* SF:for this one, is t=y:tx -> Pure t'' wp a syntactic equivalence ?
      I guess no. But where is the equivalence definition ?
   CH: It it syntactic equality. We can probably get rid of it with
       testers and selectors. *)

| TyIf0 : g:env -> e0 : exp -> e1:exp -> e2:exp -> m:eff ->
          t:typ -> wp0 : typ -> wp1 : typ -> wp2:typ ->
          typing g e0 (Cmp m tint wp0) ->
          typing g e1 (Cmp m t wp1) ->
          typing g e2 (Cmp m t wp2) ->
          typing g (EIf0 e0 e1 e2) (Cmp m t (ite m t wp0 wp1 wp2))
(* SF: I can not prove the TyIf0 case in typing_substitution if I # too many parameters *)

| TyApp : g:env -> e1:exp -> e2:exp -> m:eff -> t:typ ->
          t':typ -> wp : typ -> wp1:typ -> wp2:typ  ->
          typing g e1 (Cmp m (TArr t (Cmp m t' wp)) wp1) ->
          typing g e2 (Cmp m t wp2) ->
          kinding g (tesubst_beta e2 t') KType ->
          (* CH: Let's completely ignore this for now,
                 it's strange and I'm not sure it's really needed.
          htot:option (typing g e2 (tot t)){teappears_in 0 t' ==> is_Some htot} -> *)
          typing g (EApp e1 e2) (Cmp m (tesubst_beta e2 t')
                                     (bind m (TArr t (Cmp m t' wp)) t wp1 wp2))

| TyRet : g:env -> e:exp -> t:typ ->
          typing g e (tot t) ->
          typing g e (Cmp EfPure t (return_pure t e))

and scmp : g:env -> c1:cmp -> c2:cmp -> phi:typ -> Type =

| SCmp : #g:env -> m':eff -> #t':typ -> wp':typ ->
          m:eff{eff_sub m' m} -> #t:typ -> wp:typ -> #phi:typ ->
         =hs:styping g t' t phi ->
         =hk:kinding g wp (k_m m t) ->
         =hv:validity g (monotonic m t wp) ->
             scmp g (Cmp m' t' wp') (Cmp m t wp)
                    (tand phi (down m t (op m t timpl
                                            wp (lift m' m t' wp'))))

and styping : g:env -> t':typ -> t:typ -> phi : typ -> Type =

| SubConv : #g:env -> #t:typ -> t':typ ->
            =hv:validity g (teqtype t' t) ->
            =hk:kinding g t KType ->
                styping g t' t ttrue

| SubFun : #g:env -> #t:typ -> #t':typ -> #phi:typ ->
           #c':cmp -> #c:cmp -> #psi:typ ->
           =hst:styping g t t' phi ->
           =hsc:scmp (eextend t g) c' c psi ->
                styping g (TArr t' c') (TArr t c)
                          (tand phi (tforalle t psi))

| SubTrans : #g:env -> #t1:typ -> #t2:typ -> #t3:typ ->
             #phi12:typ -> #phi23:typ ->
             =hs12:styping g t1 t2 phi12 ->
             =hs23:styping g t2 t3 phi23 ->
                   styping g t1 t3 (tand phi12 phi23)

and kinding : g:env -> t : typ -> k:knd -> Type =

| KVar : #g:env -> x:var{is_Some (lookup_tvar g x)} ->
         =h:ewf g ->
            kinding g (TVar x) (Some.v (lookup_tvar g x))

| KConst : #g:env -> c:tconst ->
           =h:ewf g ->
              kinding g (TConst c) (tconsts c)

| KArr : #g:env -> #t1:typ -> #t2:typ -> #phi:typ -> #m:eff ->
         =hk1:kinding g t1 KType ->
         =hk2:kinding (eextend t1 g) t2 KType ->
         =hkp:kinding (eextend t1 g) phi (k_m m t2) ->
         =hv :validity (eextend t1 g) (monotonic m t2 phi) ->
              kinding g (TArr t1 (Cmp m t2 phi)) KType

| KTLam : #g:env -> #k:knd -> #t:typ -> #k':knd ->
          =hw:kwf g k ->
          =hk:kinding (textend k g) t k' ->
              kinding g (TTLam k t) (KKArr k k')

| KELam : #g:env -> #t1:typ -> #t2:typ -> #k2:knd ->
          =hk1:kinding g t1 KType ->
          =hk2:kinding (eextend t1 g) t2 k2 ->
               kinding g (TELam t1 t2) (KTArr t1 k2)

| KTApp : #g:env -> #t1:typ -> #t2:typ -> #k:knd -> k':knd ->
          =hk1:kinding g t1 (KKArr k k') ->
          =hk2:kinding g t2 k ->
          =hw :kwf g (ktsubst_beta t2 k') ->
               kinding g (TTApp t1 t2) (ktsubst_beta t2 k')

| KEApp : #g:env -> #t:typ -> #t':typ -> #k:knd -> #e:exp ->
          =hk:kinding g t (KTArr t' k) ->
          =ht:typing g e (tot t') ->
          =hw:kwf g (kesubst_beta e k) ->
              kinding g (TEApp t e) (kesubst_beta e k)

| KSub  : #g:env -> #t:typ -> #k':knd -> #k:knd -> #phi:typ ->
          =hk:kinding g t k' ->
          =hs:skinding g k' k phi ->
          =hv:validity g phi ->
              kinding g t k

and skinding : g:env -> k1:knd -> k2:knd -> phi:typ -> Type=

| KSubRefl : #g:env -> #k:knd ->
             =hw:kwf g k ->
                 skinding g k k ttrue

| KSubKArr : #g:env -> #k1:knd -> #k2:knd -> k1':knd -> k2':knd ->
             #phi1:typ -> #phi2:typ->
             =hs21 :skinding g k2 k1 phi1 ->
             =hs12':skinding (textend k2 g) k1' k2' phi2 ->
                    skinding g (KKArr k1 k1') (KKArr k2 k2')
                               (tand phi1 (tforallt k2 phi2))

| KSubTArr : #g:env -> #t1:typ -> #t2:typ -> #k1:knd -> #k2:knd ->
             #phi1:typ -> #phi2:typ ->
             =hs21:styping g t2 t1 phi1 ->
             =hs12':skinding (eextend t2 g) k1 k2 phi2 ->
                    skinding g (KTArr t1 k1) (KTArr t2 k2)
                               (tand phi1 (tforalle t2 phi2))

and kwf : env -> knd -> Type =

| WfType : g:env ->
          =h:ewf g ->
             kwf g KType

| WfTArr : #g:env -> #t:typ -> #k':knd ->
            =hk:kinding g t KType ->
            =hw:kwf (eextend t g) k' ->
                kwf g (KTArr t k')

| WfKArr : #g:env -> #k:knd -> #k':knd ->
            =hw :kwf g k ->
            =hw':kwf (textend k g) k' ->
                 kwf g (KKArr k k')

and validity : g:env -> t:typ -> Type =

| VAssume : #g:env -> x:var{is_Some (lookup_evar g x)} ->
            =h:ewf g ->
               validity g (Some.v (lookup_evar g x))

| VRedE   : #g:env -> #e:exp -> #t:typ -> #e':exp ->
            =ht :typing g e (tot t) ->
            =ht':typing g e' (tot t) ->
            =hst:epstep e e' ->
                 validity g (teqe e e')

| VEqReflE : #g:env -> #e:exp -> #t:typ ->
             =ht:typing g e (tot t) ->
                 validity g (teqe e e)

| VSubstE  : #g:env -> #e1:exp -> #e2:exp -> #t':typ -> t:typ -> x:var ->
             =hv12 :validity g (teqe e1 e2) ->
             =ht1  :typing g e1 (tot t') ->
             =ht2  :typing g e2 (tot t') ->
             =hk   :kinding (eextend t' g) t KType ->
             =hvsub:validity g (tesubst_beta e1 t) ->
                    validity g (tesubst_beta e2 t)

| VRedT    : #g:env -> #t:typ -> #t':typ -> #k:knd ->
             =hk :kinding g t k ->
             =hk':kinding g t' k ->
             =hst:tstep t t' ->
                  validity g (teqt k t t')

| VEqReflT : #g:env -> #t:typ -> #k:knd ->
             =hk:kinding g t k ->
                 validity g (teqt k t t)

| VSubstT :  #g:env -> #t1:typ -> #t2:typ -> #k:knd -> t:typ -> x:var ->
             =hv12 :validity g (teqt k t1 t2) ->
             =hk   :kinding (textend k g) t KType ->
             =hvsub:validity g (ttsubst_beta t1 t) ->
                    validity g (ttsubst_beta t2 t)

| VSelAsHeap : #g:env -> #h:heap -> #l:loc ->
               =hth:typing g (eheap h) (tot theap) ->
               =htl:typing g (eloc l) (tot tref) ->
                    validity g (teqe (esel (eheap h) (eloc l)) (eint (h l)))

| VUpdAsHeap : #g:env -> #h:heap -> #l:loc -> #i:int ->
               =hth:typing g (eheap h) (tot theap) ->
               =htl:typing g (eloc l) (tot tref) ->
               =hti:typing g (eint i) (tot tint) ->
                    validity g (teqe (eupd (eheap h) (eloc l) (eint i))
                                     (eheap (upd_heap l i h)))

| VSelEq : #g:env -> #eh:exp -> #el:exp -> #ei:exp ->
           =hth:typing g eh (tot theap) ->
           =htl:typing g el (tot tref) ->
           =hti:typing g ei (tot tint) ->
                validity g (teqe (esel (eupd eh el ei) el) ei)

| VSelNeq : #g:env -> #eh:exp -> #el:exp -> #el':exp -> #ei:exp ->
            =hth :typing g eh (tot theap) ->
            =htl :typing g el (tot tref) ->
            =htl':typing g el' (tot tref) ->
            =hti :typing g ei (tot tint) ->
            =hv  :validity g (tnot (teqe el el')) ->
                  validity g (teqe (esel (eupd eh el' ei) ei) (esel eh el))

| VForallIntro :  g:env -> t:typ -> #phi:typ ->
                 =hv:validity (eextend t g) phi ->
                     validity g (tforalle t phi)

| VForallTypIntro :  g:env -> k:knd -> #phi:typ ->
                    =hv:validity (textend k g) phi ->
                        validity g (tforallt k phi)

| VForallElim : #g:env -> #t:typ -> #phi:typ -> #e:exp ->
                =hv:validity g (tforalle t phi) ->
                =ht:typing g e (tot t) ->
                    validity g (tesubst_beta e phi)

| VForallTypElim : #g:env -> #t:typ -> #k:knd -> #phi:typ ->
                   =hv:validity g (tforallt k phi) ->
                   =hk:kinding g t k ->
                       validity g (ttsubst_beta t phi)

| VAndElim1 : #g:env -> #p1:typ -> #p2:typ ->
              =hv:validity g (tand p1 p2) ->
                  validity g p1

| VAndElim2 : #g:env -> #p1:typ -> #p2:typ ->
              =hv:validity g (tand p1 p2) ->
                  validity g p2

| VAndIntro : #g:env -> #p1:typ -> #p2:typ ->
              =hv1:validity g p1 ->
              =hv2:validity g p2 ->
                   validity g (tand p1 p2)

| VExMiddle : #g:env -> #t1:typ -> t2:typ ->
              =hk2:kinding g t2 KType ->
              =hv1:validity (eextend t1 g) (tesh t2) ->
              =hv2:validity (eextend (tnot t1) g) (tesh t2) ->
              validity g t2

| VOrIntro1 : #g:env -> #t1:typ -> #t2:typ ->
              =hv:validity g t1 ->
              =hk:kinding g t2 KType ->
                  validity g (tor t1 t2)

| VOrIntro2 : #g:env -> #t1:typ -> #t2:typ ->
              =hv:validity g t2 ->
              =hk:kinding g t1 KType ->
                  validity g (tor t1 t2)

| VOrElim : #g:env -> t1:typ -> t2:typ -> #t3:typ ->
            =hv1:validity (eextend t1 g) (tesh t3) ->
            =hv2:validity (eextend t2 g) (tesh t3) ->
            =hk :kinding g t3 KType ->
                 validity g t3

| VFalseElim : #g:env -> #t:typ ->
               =hv:validity g tfalse ->
               =hk:kinding g t KType ->
                   validity g t

| VPreceedsIntro : #g:env -> #v1:value -> #v2:value{precedes v1 v2} ->
                   #t1:typ -> #t2:typ ->
                   =ht1:typing g v1 (tot t1) ->
                   =ht2:typing g v2 (tot t2) ->
                        validity g (tprecedes v1 v2)

| VDistinctC : g:env -> c1:econst -> c2:econst{c1 <> c2} -> t:typ ->
               =h:ewf g ->
               validity g (tnot (teqe (EConst c1) (EConst c2)))

| VDistinctTH : #g:env -> #t1:typ{is_hnf t1} ->
                          #t2:typ{is_hnf t2 && not (head_eq t1 t2)} ->
                =hk1:kinding g t1 KType ->
                =hk2:kinding g t2 KType ->
                     validity g (tnot (teqtype t1 t2))

(*
For injectivity should probably stick with this (see discussion in txt file):

    G |= x:t1 -> M t2 phi =_Type x:t1' -> M t2' phi'
    -------------------------------------------- [V-InjTH]
    G |= (t1 =_Type t1) /\ (t2 = t2') /\ (phi = phi')
 *)

| VInjTH : #g:env -> #t1 :typ -> #t2 :typ -> #phi :typ ->
                     #t1':typ -> #t2':typ -> #phi':typ -> #m:eff ->
           =hv:validity g (teqtype (TArr t1  (Cmp m t2  phi))
                                   (TArr t1' (Cmp m t2' phi'))) ->
               validity g (tand (tand (teqtype t1 t1') (teqtype t2 t2))
                                      (teqtype phi phi'))

and ewf : env -> Type =

| GEmpty : ewf empty

| GType  : #g:env -> #t:typ ->
           =hk:kinding g t KType ->
               ewf (eextend t g)

| GKind  : #g:env -> #k:knd ->
           =h:kwf g k ->
              ewf (textend k g)


(**********************)
(* Substitution Lemma *)
(**********************)

(*TODO: prove all those admitted lemmas*)

val subst_on_tot : s:sub -> t:typ -> Lemma (csubst s (tot t) = tot (tsubst s t))
let subst_on_tot s t = admit()

val subst_on_ite : s:sub -> m : eff -> t:typ -> wp0:typ -> wp1:typ -> wp2:typ ->
Lemma (tsubst s (ite m t wp0 wp1 wp2) = ite m (tsubst s t) (tsubst s wp0) (tsubst s wp1) (tsubst s wp2))
let subst_on_ite m t wp0 wp1 wp2 = admit()

val subst_on_econst : s:sub -> ec:econst -> Lemma (esubst s (EConst ec) = EConst ec)
let subst_on_econst s ec = ()
val subst_on_teconst : s:sub -> ec:econst -> Lemma (tsubst s (econsts ec) = econsts ec)
let subst_on_teconst s ec = admit()

val subst_on_tarrow : s:sub -> t1:typ -> m:eff -> t2:typ -> wp:typ ->
Lemma (tsubst s (TArr t1 (Cmp m t2 wp)) = TArr (tsubst s t1) (Cmp m (tsubst (sub_elam s) t2) (tsubst (sub_elam s) wp)))
let subst_on_tarrow s t1 m t2 wp = admit()

val subst_on_elam : s:sub -> t1:typ -> ebody : exp ->
Lemma (esubst s (ELam t1 ebody) = ELam (tsubst s t1) (esubst (sub_elam s) ebody))
let subst_on_elam s t1 ebody = admit()

val subst_preserves_tarrow : s:sub -> t:typ -> Lemma (is_TArr t ==> is_TArr (tsubst s t))
let subst_preserves_tarrow s t = ()

val subst_preserves_head_const : s:sub -> t:typ -> Lemma (is_Some (head_const t) ==> is_Some (head_const (tsubst s t)))
let rec subst_preserves_head_const s t =
match t with
| TConst tc -> ()
| TTApp t1 _ -> subst_preserves_head_const s t1
| TEApp t1 _ -> subst_preserves_head_const s t1
| _ -> ()

val subst_on_hnf : s:sub -> t:typ -> Lemma ( is_hnf t ==> is_hnf (tsubst s t) )
let subst_on_hnf s t = subst_preserves_tarrow s t; subst_preserves_head_const s t

val subst_preserves_head_eq : s:sub -> t1:typ{is_hnf t1} -> t2:typ{is_hnf t2} -> Lemma (is_hnf (tsubst s t1) /\ is_hnf (tsubst s t2) /\ (not (head_eq t1 t2) ==> not (head_eq (tsubst s t1) (tsubst s t2))))
let subst_preserves_head_eq s t1 t2 = admit()
(*TODO: to prove in priority*)
(*
subst_on_hnf s t1; subst_on_hnf s t2;
if not (is_Some (head_const t1)) then ()
else ()
*)



val tsubst_elam_shift : s:sub -> t:typ -> Lemma (tsubst (sub_elam s) (tesh t) = tesh (tsubst s t))
let tsubst_elam_shift s t = admit()

val ksubst_elam_shift : s:sub -> k:knd -> Lemma (ksubst (sub_elam s) (kesh k) = kesh (ksubst s k))
let ksubst_elam_shift s k = admit()

val tyif01 : s:sub -> e0:exp -> e1:exp -> e2:exp -> Lemma (esubst s (EIf0 e0 e1 e2) = EIf0 (esubst s e0) (esubst s e1) (esubst s e2))
let tyif01 s e0 e1 e2 = ()
val tyif02 : s:sub -> m:eff -> wp0:typ -> Lemma(csubst s (Cmp m tint wp0) = Cmp m tint (tsubst s wp0))
let tyif02 s m wp0 = ()
val tyif03 : s:sub -> m:eff -> t:typ -> wp:typ -> Lemma (csubst s (Cmp m t wp) = Cmp m (tsubst s t) (tsubst s wp))
let tyif03 s m t wp = ()

val get_tlam_kinding : #g:env -> #t:typ -> #c:cmp -> hk : kinding g (TArr t c) KType -> Tot (r:kinding g t KType{r << hk})
(decreases %[hk])
let rec get_tlam_kinding g t c hk = admit()
  (*
match hk with 
| KArr hk1 _ _ _ -> hk1
| KSub hk hsk hv -> let KSubRefl hw = hsk in get_tlam_kinding hk
*)
(*SF : ^ was working at some point and now it does not -> ??? *)
type subst_typing : s:sub -> g1:env -> g2:env -> Type =
| SubstTyping : #s:sub -> #g1:env -> #g2:env -> 
                hwf1:ewf g1 ->
                hwf2:ewf g2 ->

                ef:(x:var{is_Some (lookup_evar g1 x)} -> 
                    Tot(typing g2 (Sub.es s x) (tot (tsubst s (Some.v (lookup_evar g1 x)))))) ->

                tf:(a:var{is_Some (lookup_tvar g1 a)} -> 
                    Tot(kinding g2 (Sub.ts s a) (ksubst s (Some.v (lookup_tvar g1 a))))) ->
                subst_typing s g1 g2
(*
val eh_sub_einc : g:env -> t:typ -> hk:kinding g t KType ->
x:var{is_Some (lookup_evar g x)} -> Tot( typing (eextend t g) (EVar (x+1)) (tot (tesh (Some.v (lookup_evar g x)))))
val th_sub_einc : g:env -> t:typ -> hk:kinding g t KType ->
a:var{is_Some (lookup_tvar g a)} -> 
                    Tot(kinding (eextend t g) (Sub.ts s a) (ksubst s (Some.v (lookup_tvar g1 a))))
*)
val hs_sub_einc : #g:env -> #t:typ -> hwf : ewf g -> hk:kinding g t KType ->
Tot(subst_typing sub_einc g (eextend t g))
let hs_sub_einc g t hwf hk =
let hwfgext = GType hk in
      SubstTyping hwf hwfgext 
		  (fun x -> 
			     TyVar (x+1) hwfgext
		  ) 
		  (fun x -> KVar x hwfgext)
(*
opaque val substitution :
      #g1:env -> #e:exp -> #t:typ -> s:esub -> #g2:env ->
      h1:typing g1 e t ->
      hs:subst_typing s g1 g2 ->
      Tot (typing g2 (esubst s e) t)
     (decreases %[is_var e; is_renaming s; h1])
*)
val typing_substitution : #g1:env -> #e:exp -> #c:cmp -> s:sub -> #g2:env ->
    h1:typing g1 e c ->
    hs:subst_typing s g1 g2 ->
    Tot (typing g2 (esubst s e) (csubst s c))
(decreases %[is_evar e; is_renaming s; h1])
val scmp_substitution : #g1:env -> #c1:cmp -> #c2:cmp -> #phi:typ -> s:sub -> #g2:env ->
    h1:scmp g1 c1 c2 phi ->
    hs:subst_typing s g1 g2 ->
    Tot (scmp g2 (csubst s c1) (csubst s c2) (tsubst s phi))
(decreases %[1; is_renaming s; h1])
val styping_substitution : #g1:env -> #t':typ -> #t:typ -> #phi:typ -> s:sub -> #g2:env ->
    h1:styping g1 t' t phi ->
    hs:subst_typing s g1 g2 ->
    Tot (styping g2 (tsubst s t') (tsubst s t) (tsubst s phi))
(decreases %[1;is_renaming s; h1])
val kinding_substitution : g1:env -> #t:typ -> #k:knd -> s:sub -> g2:env ->
    h1:kinding g1 t k ->
    hs:subst_typing s g1 g2 ->
    Tot (kinding g2 (tsubst s t) (ksubst s k))
(decreases %[is_tvar t; is_renaming s; h1])
val skinding_substitution : #g1:env -> #k1:knd -> #k2:knd -> #phi:typ -> s:sub -> #g2:env -> 
    h1:skinding g1 k1 k2 phi ->
    hs:subst_typing s g1 g2 ->
    Tot (skinding g2 (ksubst s k1) (ksubst s k2) (tsubst s phi))
(decreases %[1; is_renaming s; h1])
val kwf_substitution : #g1:env -> #k:knd -> s:sub -> #g2:env ->
    h1:kwf g1 k ->
    hs:subst_typing s g1 g2 ->
    Tot (kwf g2 (ksubst s k))
(decreases %[1;is_renaming s; h1])
val validity_substitution : #g1:env -> #t:typ -> s:sub -> #g2:env ->
    h1:validity g1 t ->
    hs:subst_typing s g1 g2 ->
    Tot (validity g2 (tsubst s t))
(decreases %[1;is_renaming s; h1])
val hs_sub_elam : s:sub -> #g1:env -> #g2:env -> #t:typ ->
hk   : kinding g1 t KType ->
hs   : subst_typing s g1 g2 ->
Tot (subst_typing (sub_elam s) (eextend t g1) (eextend (tsubst s t) g2))
(decreases %[1;is_renaming s; hk])
(*
val ehs_sub_elam : s:sub -> #g1 : env -> #g2 : env -> #t:typ ->
hwf1 : ewf g1 ->
hwf2 : ewf g2 ->
hk : kinding g1 t KType ->
hs : subst_typing s g1 g2 ->
(x:var{is_Some (lookup_evar (eextend t g1) x)} -> 
                    Tot(typing (eextend (tsubst s t ) g2) (Sub.es (sub_elam s) x) (tot (tsubst (sub_elam s) (Some.v (lookup_evar (eextend t g1) x))))))
val ths_sub_elam : s:sub -> #g1 : env -> #g2 : env -> #typ ->
hwf1 : ewf g1 ->
hwf2 : ewf g2 ->
hk : kinding g1 t KType ->
hs : subst_typing s g1 g2 ->
(a:var{is_Some (lookup_tvar (eextend t g1) a)} ->
 Tot (kinding (eextend (tsubst s t) g2) (Sub.ts (sub_elam s) a) (ksubst (sub_elam s) (Some.v (lookup_tvar (eextend t g1) a)))))
*)
(*
val typing_substitution : #g1:env -> #e:exp -> #c:cmp -> s:sub -> #g2:env ->
    h1:typing g1 e c ->
    hs:subst_typing s g1 g2 ->
    Tot (typing g2 (esubst s e) (csubst s c))
*)
let rec typing_substitution g1 e c s g2 h1 hs = 
match h1 with 
| TyVar #g1 x hk -> (subst_on_tot s (Cmp.t c); SubstTyping.ef hs x)
| TyConst g ec hwf ->
admit()
  (*
    (subst_on_econst s ec;
     subst_on_tot s (econsts ec);
     subst_on_teconst s ec;
     TyConst g2 ec (SubstTyping.hwf2 hs))
    *)
| TyIf0 g e0 e1 e2 m t wp0 wp1 wp2 he0 he1 he2 -> 
admit()
  (*
    (
      subst_on_ite s m t wp0 wp1 wp2;
      tyif01 s e0 e1 e2;
      tyif02 s m wp0;
      tyif03 s m t wp1;
      tyif03 s m t wp2;
      let he0' : typing g2 (esubst s e0) (Cmp m tint (tsubst s wp0)) = typing_substitution s he0 hs in 
      let he1' : typing g2 (esubst s e1) (Cmp m (tsubst s t) (tsubst s wp1)) = typing_substitution s he1 hs in
      let he2' : typing g2 (esubst s e2) (Cmp m (tsubst s t) (tsubst s wp2)) = typing_substitution s he2 hs in 
      let h1'  : typing g2 (EIf0 (esubst s e0) (esubst s e1) (esubst s e2)) (Cmp m (tsubst s t) (ite m (tsubst s t) (tsubst s wp0) (tsubst s wp1) (tsubst s wp2))) = 
	  TyIf0 g2 (esubst s e0) (esubst s e1) (esubst s e2) m (tsubst s t) (tsubst s wp0) (tsubst s wp1) (tsubst s wp2) he0' he1' he2' in 
      h1'
    )
    *)
| TyAbs #g1 #t1 #ebody m t2 wp hk hbody  -> 
admit()
  (*
    (
    let hwfg1ext : ewf (eextend t1 g1) = GType hk in
    let hkt1g2 : kinding g2 (tsubst s t1) KType = kinding_substitution s hk hs in
    let hwfg2ext : ewf (eextend (tsubst s t1) g2) = GType hkt1g2 in
    let hs'' : subst_typing sub_einc g2 (eextend (tsubst s t1) g2) =
      SubstTyping (SubstTyping.hwf2 hs) hwfg2ext 
		  (fun x -> 
			     TyVar (x+1) hwfg2ext
		  ) 
		  (fun x -> KVar x hwfg2ext) in
    let hs' : subst_typing (sub_elam s) (eextend t1 g1) (eextend (tsubst s t1) g2) =
    SubstTyping hwfg1ext hwfg2ext 
      (fun x -> match x with 
		| 0 -> (*TyVar 0 hwg2ext -> typing g2ext (EVar 0) (tot (tesh (tsubst s t1)))
			elam_shift       -> typing g2ext (EVar 0) (tot (tsubst (sub_elam s) (tesh t1)))*)
			(tsubst_elam_shift s t1;
			 TyVar 0 hwfg2ext)
		| n -> ( 
		       (*hg2   -> typing g2 (s.es (x-1)) (tot (tsubst s (g1 (x-1))))*) 
		       (*ind   -> typing g2ext (eesh s.ex (x-1)) (cesh (tot (tsubst s (g1 (x-1))))) *)
		       (*subst_on_tot -> typing g2ext (eesh s.ex (x-1)) (tot (tesh (tsubst s (g1 (x-1)))))*)
		       (*elam_shift -> typing g2ext (eesh s.ex (x-1)) (tot (tsubst (sub_elam s) (tesh (g1 (x-1))))) *)
		       (* =    -> typing g2ext (esub_elam x) (tot (tsubst (sub_elam s) (g1ext x)))*)
		       let hg2 = SubstTyping.ef hs (x-1) in
		       let hg2ext = typing_substitution sub_einc hg2 hs'' in
		       subst_on_tot sub_einc (tsubst s (Some.v (lookup_evar g1 (x-1))));
		       tsubst_elam_shift s (Some.v (lookup_evar g1 (x-1)));
		       hg2ext
		       )
      )
      (fun a -> let hkg2 = SubstTyping.tf hs a in
		(*hkg2    -> kinding g2 (s.tf a) (ksubst s (g1 a)) *)
		let hkg2ext = kinding_substitution sub_einc hkg2 hs'' in
		(*hkg2ext -> kinding g2ext (tesh (s.tf a)) (kesh (ksubst s (g1 a)))*)
		(*elam_shift -> kinding g2ext (tesh (s.tf a)) (ksubst (sub_elam s) (kesh (g1 a)))*)
		ksubst_elam_shift s (Some.v (lookup_tvar g1 a));
		hkg2ext
      )
    in
    let hbodyg2ext : typing (eextend (tsubst s t1) g2) (esubst (sub_elam s) ebody) (Cmp m (tsubst (sub_elam s) t2) (tsubst (sub_elam s) wp)) = typing_substitution (sub_elam s) hbody hs' in
    (*hbodyg2ext -> typing (eextend (tsubst s t1) g2) (esubst (sub_elam s) ebody) (Cmp m (tsubst s t2) (tsubst s wp)) *)
    let habsg2ext = TyAbs m (tsubst (sub_elam s) t2) (tsubst (sub_elam s) wp) hkt1g2 hbodyg2ext in
    (*habsg2ext  -> typing g2 (ELam (tsubst s t1) (esubst (sub_elam s) ebody)) (tot (TArr (tsubst s t1) (Cmp m (tsubst (sub_elam s) t2) (tsubst (sub_elam s) wp))))*)
    subst_on_elam s t1 ebody;
    subst_on_tarrow s t1 m t2 wp;
    subst_on_tot s (TArr t1 (Cmp m t2 wp));
    habsg2ext
    )
    *)
| TyFix #g #tx #t' #d #t'' #wp #ebody hktarr htd htbody -> (
    (*
    let hktlam : kinding g1 tx KType = get_tlam_kinding hktarr in
    let hktarrg2 : kinding g2 (TArr (tsubst s tx) (Cmp EfPure (tsubst (sub_elam s) t'') (tsubst (sub_elam s) wp))) KType = magic () (*this one is "easy"*) in
    let g1' = eextend tx g1 in
    let g2' = eextend (tsubst s tx) g2 in
    let s' = sub_elam s in
    let hwfg1 = SubstTyping.hwf1 hs in
    let hwfg1' = GType hktlam in
    let hwfg2 = SubstTyping.hwf2 hs in
    let hwfg2' = GType (kinding_substitution s hktlam hs) in
    (*
    let hsg1g1' = hs_sub_einc (SubstTyping.hwf1 hs) hktlam in
    let hsg2g2' = hs_sub_einc (SubstTyping.hwf2 hs) (kinding_substitution s hktlam hs) in
    *)
    let hsg1g1' : subst_typing sub_einc g1 g1' = hs_sub_einc hwfg1 hktlam in
    
    let hsg1'g2' : subst_typing s' g1' g2' = hs_sub_elam s hktlam hs in
(*OK until this point ^*)
    let tfung1' = tesh (TArr tx (Cmp EfPure t'' (tfix_wp tx t'' d wp))) in
    let tfung2' = tsubst s' tfung1' in
    let hktfung1' : kinding g1' tfung1' KType = magic() (*TODO: remove the magic. we will need to prove that tfix_wp tx t'' d wp is well kinded out of a proof of kinding of wp *) in
(*
    let g1'' = eextend tfung1' g1' in
    let g2'' = eextend tfung2' g2' in
    let s'' = sub_elam s' in
    let hsg1''g2'' : subst_typing s'' g1'' g2'' = magic() (*TODO: here we can not use hs_sub_elam since we do not know anything aout hktfung1' *) in 
   *) 
*)
    admit()





)
| TyFixOmega g tx t' wp ebody hkarr htbody ->
    let hktlam : kinding g1 tx KType = get_tlam_kinding hkarr in
    let hktarrg2 : kinding g2 (TArr (tsubst s tx) (Cmp EfAll (tsubst (sub_elam s) t') (tsubst (sub_elam s) wp))) KType = subst_on_tarrow s tx EfAll t' wp; kinding_substitution g1 s g2 hkarr hs in
    let g1' = eextend tx g1 in
    let g2' = eextend (tsubst s tx) g2 in
    let s' = sub_elam s in
    let hwfg1 : ewf g1 = SubstTyping.hwf1 hs in
    let hwfg1' : ewf g1' = GType hktlam in
    let hwfg2 : ewf g2 = SubstTyping.hwf2 hs in
    let hwfg2' : ewf g2' = GType (kinding_substitution g1 s g2 hktlam hs) in
    let hsg1g1' : subst_typing sub_einc g1 g1' = hs_sub_einc hwfg1 hktlam in
    let hsg2g2' : subst_typing sub_einc g2 g2' = hs_sub_einc hwfg2 (kinding_substitution g1 s g2 hktlam hs) in
    let hsg1'g2' : subst_typing s' g1' g2' = hs_sub_elam s hktlam hs in
    let sdiag = sub_comp sub_einc s in
    let hsg1g2' : subst_typing sdiag g1 g2' =
    (* Commenting the code to gain some seconds of compilation … *)
  (*
    SubstTyping hwfg1 hwfg2'
    (fun x -> let tg1 = Some.v (lookup_evar g1 x) in
              let eg2 = Sub.es s x in
              let htg2 : typing g2 eg2 (tot (tsubst s tg1)) = SubstTyping.ef hs x in 
              let htg2' : typing g2' (eesh eg2) (csubst sub_einc (tot (tsubst s tg1))) = typing_substitution sub_einc htg2 hsg2g2' in
	      let htg2'p : typing g2' (eesh eg2) (tot (tsubst sdiag tg1)) = subst_on_tot sub_einc (tsubst s tg1); tsubst_comp sub_einc s tg1; htg2' in
	      htg2'p
     )
    (fun a -> let kg1 = Some.v (lookup_tvar g1 a) in
              let tg2 = Sub.ts s a in
	      let hkg2 : kinding g2 tg2 (ksubst s kg1) = SubstTyping.tf hs a in
	      let htg2': kinding g2' (tesh tg2) (kesh (ksubst s kg1)) = kinding_substitution g2 sub_einc g2' hkg2 hsg2g2' in
	      ksubst_comp sub_einc s kg1; htg2'
    )
*)   
  magic()
    in
    let tfung1 = TArr tx (Cmp EfAll t' wp) in
(*OK until this point ^*)
    let tfung1' = tesh tfung1 in
    let tfung2' = tsubst sdiag tfung1 in
    let hkarrg1' : kinding g1' tfung1' KType = kinding_substitution g1 #tfung1 sub_einc g1' hkarr hsg1g1' in
    let hkarr : kinding g1 tfung1 KType = hkarr in
    let hkarrg2' : kinding g2' tfung2' KType = kinding_substitution g1 sdiag g2' hkarr (hsg1g2') in

    let g1'' = eextend tfung1' g1' in
    let g2'' = eextend tfung2' g2' in
    let hwfg1'' : ewf g1'' = GType hkarrg1' in
   let hwfg2'' : ewf g2'' = GType hkarrg2' in
   let hsg2'g2'' : subst_typing sub_einc g2' g2'' = hs_sub_einc hwfg2' hkarrg2' in
   let s2 = sub_elam (sub_elam s) in
   let hsg1''g2'' : subst_typing s2 g1'' g2'' =
    (* Commenting the code to gain some seconds of compilation … *)
  (*
     SubstTyping (hwfg1'') (hwfg2'') 
     (fun x -> match x with
        | 0 -> (
		tsubst_elam_shift (sub_elam s) (tesh tfung1);
		let ht : typing g2'' (EVar 0) (tot (tesh (tsubst sdiag tfung1))) = TyVar 0 hwfg2'' in
		tsubst_comp sub_einc s tfung1;
		let ht' : typing g2'' (EVar 0) (tot (tesh (tesh (tsubst s tfung1)))) = ht in

	  	tsubst_elam_shift s tfung1;
		let ht'' : typing g2'' (EVar 0) (tot (tesh (tsubst (sub_elam s) (tesh tfung1)))) = ht' in
		tsubst_elam_shift (sub_elam s) (tesh tfung1);
		let htppp : typing g2'' (EVar 0) (tot (tsubst (sub_elam (sub_elam s)) (tesh (tesh tfung1)))) = ht'' in
		subst_on_tot (sub_elam (sub_elam s)) (tesh (tesh tfung1));
		htppp
		)
	| n -> (let eg2' = Sub.es (sub_elam s) (x-1) in
	        let teg1' = Some.v (lookup_evar g1' (x-1))  in
	        let hg2' : typing g2' eg2' (tot (tsubst (sub_elam s) teg1')) = SubstTyping.ef hsg1'g2' (x-1) in
	        let hg2'' : typing g2'' (eesh eg2') (csubst sub_einc (tot (tsubst (sub_elam s) teg1'))) = typing_substitution sub_einc hg2' hsg2'g2'' in
		subst_on_tot sub_einc (tsubst (sub_elam s) teg1');
		let hg2ppp : typing g2'' (eesh eg2') (tot (tesh (tsubst (sub_elam s) teg1'))) = hg2'' in
		tsubst_elam_shift (sub_elam s) teg1';
		hg2ppp

	       )
	       
     )
     (fun a -> let hkg2' = SubstTyping.tf hsg1'g2' a in
               let hkg2'' = kinding_substitution g2' sub_einc g2'' hkg2' hsg2'g2'' in
	       ksubst_elam_shift (sub_elam s) (Some.v (lookup_tvar g1' a));
	       hkg2'' 
      ) 
     *) magic()
     in
     (*SF : I really do not know what to do to make the next line compile … *)
  (*
     let htbodyg2'' : typing g2'' (esubst s2 ebody) (csubst s2 (Cmp EfAll (tesh t') (tesh wp))) = typing_substitution s2 htbody hsg1''g2'' in
  *)
    admit()
| _ -> admit()
and scmp_substitution g1 c1 c2 phi s g2 h1 hs = admit()
and styping_substitution g1 t' t phi s g2 h1 hs = admit()
and kinding_substitution g1 t k s g2 h1 hs = admit()
and skinding_substitution g1 k1 k2 phi s g2 h1 hs = admit()
and kwf_substitution g1 k s g2 h1 hs = admit()
and validity_substitution g1 t s g2 h1 hs = admit()
and hs_sub_elam s g1 g2 t hk hs = admit()

module VerifyOnlyThis

open TinyFStarNew

(* CH: TODO: How about starting directly with the substitution lemma
             and only prove what's needed for that. Could it be it
             doesn't even need derived judgments? *)

(* Derived kinding rules -- TODO: need a lot more *)

(* derived judgments (small part) *)
opaque val kinding_ewf : #g:env -> #t:typ -> #k:knd ->
                  =hk:kinding g t k ->
                 Tot (ewf g)
let kinding_ewf g t k hk = admit()

(* This takes forever to typecheck and fails without the assert;
   plus this fails without the explicit type annotation on k' in KTApp
   (Unresolved implicit argument). Filed as #237.
val k_foralle : #g:env -> #t1:typ -> #t2:typ ->
                =hk1:kinding g t1 KType ->
                =hk2:kinding (eextend t1 g) t2 KType ->
                Tot (kinding g (TTApp (TConst TcForallE) t1)
                               (KKArr (KTArr t1 KType) KType))
let k_foralle g t1 t2 hk1 hk2 =
  let gwf = kinding_ewf hk1 in
  (* assert(KKArr (KTArr t1 KType) KType =  *)
  (*        ktsubst_beta t1 (KKArr (KTArr (TVar 0) KType) KType)); *)
  KTApp (KKArr (KTArr (TVar 0) KType) KType) (KConst TcForallE gwf) hk1 (magic())
*)

val k_foralle : #g:env -> #t1:typ -> #t2:typ ->
                =hk1:kinding g t1 KType ->
                =hk2:kinding (eextend t1 g) t2 KType ->
                Tot (kinding g (tforalle t1 t2) KType)
let k_foralle g t1 t2 hk1 hk2 = admit()
(* TODO: finish this -- it takes >10s to check (admitting)
  let gwf = kinding_ewf hk1 in
  let tres x = KKArr (KTArr x KType) KType in
     (* using tres doesn't work, god damn it! Had to unfold it. File this shit. *)
  let happ1 : (kinding g (TTApp (TConst TcForallE) t1)
                         (KKArr (KTArr t1 KType) KType)) =
    KTApp (KKArr (KTArr (TVar 0) KType) KType) (KConst TcForallE gwf) hk1 (magic())
          (* (WfKArr (magic()) (\*WfTArr (magic())*\) *)
          (*                 (WfType (eextend (TVar 0) g)) *)
          (*         (WfType (textend KType g))) *)
  in magic() (* KTApp KType happ1 hk2 (WfType g) *)
*)

val k_impl : #g:env -> #t1:typ -> #t2:typ ->
            =hk1:kinding g t1 KType ->
            =hk2:kinding g t2 KType ->
            Tot (kinding g (timpl t1 t2) KType)
let k_impl g t1 t2 hk1 hk2 = admit()
(* TODO: this needs updating:
  let happ1 : (kinding g (TTApp (TConst TcImpl) t1) (KKArr KType KType)) =
    KTApp (KKArr KType KType) (KConst g TcImpl) hk1
          (WfKArr (WfType g) (WfType (textend g KType)))
  in KTApp KType happ1 hk2 (WfType g)
*)

val k_false : #g:env -> =hewf:(ewf g) -> Tot (kinding g tfalse KType)
let k_false g hewf = KConst TcFalse hewf

val k_not : #g:env -> #t:typ ->
           =hk:kinding g t KType ->
           Tot (kinding g (tnot t) KType)
let k_not g t hk = k_impl hk (k_false (kinding_ewf hk))

(* TODO: need to prove derived judgment and weakening before we can
   prove some of the derived validity rules! For us weakening is just
   an instance of (expression) substitution, so we also need
   substitution. All this works fine only if none of these proofs rely
   on things like v_of_intro1; at this point I don't see why the wouldn't. *)

(* Derived validity rules *)

(* CH: TODO: trying to encode as many logical connectives as possible
             to reduce the number of rules here (prove them as lemmas) *)

val v_impl_intro : #g:env -> t1:typ -> t2:typ ->
                   =hv:validity (eextend t1 g) (tesh t2) ->
                  Tot (validity g (timpl t1 t2))
let v_impl_intro g t1 t2 hv= VForallIntro g t1 hv

val v_impl_elim : #g:env -> #t1:typ -> #t2:typ ->
                 =hv12:validity g (timpl t1 t2) ->
                 =hv1 :validity g t1 ->
                  Tot (validity g t2)
let v_impl_elim = admit()

val v_true : #g:env -> =hewf:ewf g -> Tot (validity g ttrue)
let v_true g hewf = v_impl_intro tfalse tfalse
                            (VAssume 0 (GType (k_false hewf)))

    (* CH: Can probably derive V-ExMiddle from: *)

    (* G, _:~t |= t *)
    (* ----------- [V-Classical] *)
    (* G |= t *)

    (*     of, even better, from this *)

    (* G, _:~t |= false *)
    (* --------------- [V-Classical] *)
    (* G |= t *)

(* Should follow without VExMiddle *)
val v_not_not_intro : #g:env -> #t:typ ->
                      =hv:validity g t ->
                          validity g (tnot (tnot t))
let v_not_not_intro = admit()

(* Should follow from VExMiddle (it's equivalent to it) *)
val v_not_not_elim : #g:env -> t:typ ->
                     =hv:validity g (tnot (tnot t)) ->
                         validity g t
let v_not_not_elim = admit()

(* Sketch for v_or_intro1

       g |= t1
       ------------ weakening!   ------------- VAssume
       g, ~t1 |= t1              g, ~t1 |= ~t1
       --------------------------------------- VImplElim
                 g, ~t1 |= false
                 --------------- VFalseElim
                  g, ~t1 |= t2
                 --------------- VImplIntro
                 g |= ~t1 ==> t2
 *)
val v_or_intro1 : #g:env -> #t1:typ -> #t2:typ ->
                  =hv1:validity g t1 ->
                  =hk2:kinding g t2 KType ->
                       validity g (tor t1 t2)
let v_or_intro1 g t1 t2 hv1 hk2 =
  v_impl_intro (tnot t1) t2
               (magic())

val v_or_intro2 : #g:env -> #t1:typ -> #t2:typ ->
                  =hv:validity g t2 ->
                  =hk:kinding g t1 KType ->
                      validity g (tor t1 t2)
let v_or_intro2 = admit()

(* CH: TODO: so far didn't manage to derive this on paper,
             might need to add it back as primitive! *)
val v_or_elim : #g:env -> t1:typ -> t2:typ -> #t3:typ ->
                =hv :validity g (tor t1 t2) ->
                =hv1:validity (eextend t1 g) (tesh t3) ->
                =hv2:validity (eextend t2 g) (tesh t3) ->
                =hk :kinding g t3 KType ->
                     validity g t3
let v_or_elim = admit()

(* CH: TODO: prove symmetry and transitivity of equality as in the F7
   paper from VEqRefl and VSubst; this will save us 4 rules *)

val v_eq_trane : #g:env -> #e1:exp -> #e2:exp -> #e3:exp ->
             =hv12:validity g (teqe e1 e2) ->
             =hv23:validity g (teqe e2 e3) ->
                   validity g (teqe e1 e3)
let v_eq_trane = admit()

val v_eq_syme : #g:env -> #e1:exp -> #e2:exp ->
             =hv:validity g (teqe e1 e2) ->
                 validity g (teqe e2 e1)
let v_eq_syme = admit()

val v_eq_trant : #g:env -> #t1:typ -> #t2:typ -> #t3:typ -> #k:knd ->
             =hv12:validity g (teqt k t1 t2) ->
             =hv23:validity g (teqt k t2 t3) ->
                   validity g (teqt k t1 t3)
let v_eq_trant = admit()

val v_eq_symt : #g:env -> #t1:typ -> #t2:typ -> #k:knd ->
            =hv:validity g (teqt k t1 t2) ->
                validity g (teqt k t2 t1)
let v_eq_symt = admit()
