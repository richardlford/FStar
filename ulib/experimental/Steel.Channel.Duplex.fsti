(*
   Copyright 2020 Microsoft Research

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*)

module Steel.Channel.Duplex
open Steel.Channel.Protocol
open Steel.Effect
open Steel.Memory

/// Msg int (fun x -> Msg (y:int { y > x }) (fun _ -> Ret unit))
///
/// DoWhile (Msg int (fun x -> Msg (y:int { y > x }) (fun _ -> Ret bool)))
let prot : Type u#1 = protocol unit

val chan (p:prot) : Type0

val endpoint (#p:prot) (c:chan p) (next_action:prot) : slprop u#1

val new_chan (p:prot)
  : SteelT (chan p) emp (fun c -> endpoint c p `star` endpoint c (dual p))

val send (#p:prot)
         (c:chan p)
         (#next:prot{more next /\ tag_of next = Send})
         (x:msg_t next)
  : SteelT unit
           (endpoint c next)
           (fun _ -> endpoint c (step next x))

val recv (#p:prot)
         (#next:prot{more next /\ tag_of next = Recv})
         (c:chan p)
  : SteelT (msg_t next)
           (endpoint c next)
           (fun x -> endpoint c (step next x))

val history (#p:prot) (c:chan p) (t:partial_trace_of p) : slprop

val history_duplicable (#p:prot) (c:chan p) (t:partial_trace_of p)
  : SteelT unit (history c t) (fun _ -> history c t `star` history c t)

val trace (#q:prot) (cc:chan q)
  : SteelT (partial_trace_of q) emp (fun tr -> history cc tr)

val extend_trace (#p:prot) (#next:prot) (c:chan p) (previous:partial_trace_of p)
  : SteelT (extension_of previous)
           (endpoint c next `star` history c previous)
           (fun t -> endpoint c next `star` history c t `star` pure (until t == next))
