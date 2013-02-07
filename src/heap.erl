%%
%% Copyright © 2013 Aggelos Giantsios
%%

%% Permission is hereby granted, free of charge, to any person obtaining a copy of this software 
%% and associated documentation files (the “Software”), to deal in the Software without restriction, 
%% including without limitation the rights to use, copy, modify, merge, publish, distribute, 
%% sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is 
%% furnished to do so, subject to the following conditions:

%% The above copyright notice and this permission notice shall be included 
%% in all copies or substantial portions of the Software.

%% THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED 
%% TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
%% IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN 
%% CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

%%
%% Min-Heap, Max-Heap, Priority Queue
%%

%% This module implements min-heaps and max-heaps for use in priority queues.
%% Each value in the heap is assosiated with a reference so that the user can change its priority in O(log n).
%%
%% The implementation is based on ETS tables for the O(1) lookup time.
%% It supports all the basic heap operations:
%% *  min/1, max/1 in O(1)
%% *  take_min/1, take_max/1 in O(log n)
%% *  insert/2 in O(log n)
%% *  update/3 in O(log n)
%% *  from_list/2 in Θ(n)


-module(heap).

%% External Exports
-export([new/1, heap_size/1, is_empty/1, max/1, min/1, insert/2, delete/1, 
         take_min/1, take_max/1, update/3, from_list/2, to_list/1]).

%% Exported Types
-export_type([mode/0, heap/0]).

%% Types Declarations
-record(heap, {
  mode :: mode(),
  htab :: ets:tab()
}).
-opaque heap()  :: #heap{}.
-type mode()    :: 'max' | 'min'.
-type refterm() :: {term(), reference()}.

%% =======================================================================
%% External Exports
%% =======================================================================

%% Get a list of the terms in a heap()
-spec to_list(heap()) -> [term()].

to_list(H) ->
  L = ets:tab2list(H#heap.htab),
  M = fun(A) ->
    case A of
      {_, {_, _}} -> 'true';
      _ -> 'false'
    end
  end,
  LL = lists:filter(M, L),
  lists:map(fun({_, {X, _}}) -> X end, LL).

%% -----------------------------------------------------------------------
%% Creates an empty heap
%% -----------------------------------------------------------------------
-spec new(mode()) -> heap().

new(M) when M =:= 'max'; M=:= 'min' ->
  H = ets:new(?MODULE, ['ordered_set', 'public']),
  ets:insert(H, {'size', 0}),
  #heap{mode=M, htab=H};
new(_Mode) ->
  erlang:error('badarg').
  
%% -----------------------------------------------------------------------
%% Deletes a heap
%% -----------------------------------------------------------------------
-spec delete(heap()) -> 'true'.

delete(H) ->
  ets:delete(H#heap.htab).

%% -----------------------------------------------------------------------
%% Returns the number of elements the Heap contains
%% -----------------------------------------------------------------------
-spec heap_size(heap()) -> non_neg_integer().

heap_size(H) ->
  [{'size', Len}] = ets:lookup(H#heap.htab, 'size'),
  Len.
  
%% -----------------------------------------------------------------------
%% Checks whether Heap is an empty heap or not
%% -----------------------------------------------------------------------
-spec is_empty(heap()) -> boolean().

is_empty(H) ->
  heap_size(H) =:= 0.
  
%% -----------------------------------------------------------------------
%% Returns the element of the heap with the maximum priority.
%% If Heap is a minimum priority heap, it returns {error, min_heap}
%% -----------------------------------------------------------------------
-spec max(heap()) -> term() | {'error', 'min_heap' | 'empty_heap'}.

max(H) when H#heap.mode =:= 'max' ->
  case ets:lookup(H#heap.htab, 1) of
    [] -> {'error', 'empty_heap'};
    [{1, {Max, _Ref}}] -> Max
  end;
max(_H) ->
  {'error', 'min_heap'}.
  
%% -----------------------------------------------------------------------
%% Returns the element of the heap with the minimum priority.
%% If Heap is a maximum priority heap, it returns {error, max_heap}
%% -----------------------------------------------------------------------
-spec min(heap()) -> term() | {'error', 'max_heap' | 'empty_heap'}.
       
min(H) when H#heap.mode =:= 'min' ->
  case ets:lookup(H#heap.htab, 1) of
    [] -> {'error', 'empty_heap'};
    [{1, {Min, _Ref}}] -> Min
  end;
min(_H) ->
  {'error', 'max_heap'}.
  
%% -----------------------------------------------------------------------
%% Add a new element to the Heap and returns a tuple with the element
%% and a reference so that one can change its priority
%% -----------------------------------------------------------------------
-spec insert(heap(), term()) -> refterm().
  
insert(H, X) ->
  HS = heap_size(H),
  HS_n = HS + 1,
  Ref = erlang:make_ref(),
  ets:insert(H#heap.htab, {HS_n, {X, Ref}}),
  ets:insert(H#heap.htab, {Ref, HS_n}),
  ets:insert(H#heap.htab, {size, HS_n}),
  I = HS_n,
  P = I div 2,
  insert_loop(H, I, P),
  {X, Ref}.
    
%% -----------------------------------------------------------------------
%% Removes and returns the max
%% -----------------------------------------------------------------------
-spec take_max(heap()) -> term() | {'error', 'min_heap' | 'empty_heap'}.
         
take_max(H) when H#heap.mode =:= 'max' ->
  pop(H);
take_max(_H) ->
  {'error', 'min_heap'}.

%% -----------------------------------------------------------------------
%% Removes and returns the min
%% -----------------------------------------------------------------------
-spec take_min(heap()) -> term() | {'error', 'max_heap' | 'empty_heap'}.
         
take_min(H) when H#heap.mode =:= 'min' ->
  pop(H);
take_min(_H) ->
  {'error', 'max_heap'}.

%% -----------------------------------------------------------------------
%% Deletes and returns the element at the top of the heap
%% and re-arranges the rest of the heap
%% -----------------------------------------------------------------------
-spec pop(heap()) -> term().
  
pop(H) ->
  case ets:lookup(H#heap.htab, 1) of
    [] ->
      {'error', 'empty_heap'};
    [{1, {Head, RefHead}}] ->
      HS = heap_size(H),
      [{HS, {X, RefX}}] = ets:lookup(H#heap.htab, HS),
      ets:delete(H#heap.htab, HS),                      %% Can be commented
      ets:delete(H#heap.htab, RefHead),                 %% Can be commented
      HS_n = HS - 1,
      ets:insert(H#heap.htab, {size, HS_n}),
      case HS_n =:= 0 of                                %% Can be commented
        'true'  -> 'ok';                                %% Can be commented
        'false' ->                                      %% Can be commented
          ets:insert(H#heap.htab, {1, {X, RefX}}),
          ets:insert(H#heap.htab, {RefX, 1})
      end,                                              %% Can be commented
      combine(H, 1, HS_n),
      Head
  end.

%% -----------------------------------------------------------------------
%% Changes the priority of the element referenced with Ref to Value
%% and then re-arranges the heap
%% -----------------------------------------------------------------------
-spec update(heap(), reference(), term()) -> 'true'.
  
update(H, Ref, X) ->
  case ets:lookup(H#heap.htab, Ref) of
    [] ->
      'true';
    [{Ref, I}] ->
      [{I, {OldX, Ref}}] = ets:lookup(H#heap.htab, I),
      case {X > OldX, H#heap.mode} of
        {'true',  'max'} -> up_heapify(H, I, X, Ref);
        {'false', 'min'} -> up_heapify(H, I, X, Ref);
        {'false', 'max'} -> down_heapify(H, I, X, Ref);
        {'true',  'min'} -> down_heapify(H, I, X, Ref)
      end,
      'true'
  end.

%% -----------------------------------------------------------------------
%% Create a heap from a list of terms
%% -----------------------------------------------------------------------
-spec from_list(mode(), [term()]) -> {heap(), [refterm()]}.

from_list(M, L) when is_list(L), is_atom(M) ->
  HS = erlang:length(L),
  {H, Rs} = ets_from_elements(M, L, HS),
  I = HS div 2,
  construct_heap(H, I, HS),
  {H, Rs};
from_list(_M, _L) ->
  erlang:error('badarg').  
  
%% =======================================================================
%% Internal Functions
%% =======================================================================

%% Re-arranges the heap in a bottom-up manner
-spec insert_loop(heap(), pos_integer(), pos_integer()) -> 'ok'.

insert_loop(H, I, P) when I > 1 ->
  [{I, {X, _RefX}}] = ets:lookup(H#heap.htab, I),
  [{P, {Y, _RefY}}] = ets:lookup(H#heap.htab, P),
  case {Y < X, H#heap.mode} of
    {true, max} ->
      swap(H, P, I),
      NI = P,
      NP = NI div 2,
      insert_loop(H, NI, NP);
    {false, min} ->
      swap(H, P, I),
      NI = P,
      NP = NI div 2,
      insert_loop(H, NI, NP);
    {_, _} ->
      'ok'
  end;
insert_loop(_H, _I, _P) -> ok.

-spec up_heapify(heap(), pos_integer(), term(), reference()) -> 'ok'.

up_heapify(H, I, X, Ref) ->
  ets:insert(H#heap.htab, {I, {X, Ref}}),
  P = I div 2,
  insert_loop(H, I, P).

%% Re-arranges the heap in a top-down manner
-spec combine(heap(), pos_integer(), pos_integer()) -> 'ok'.

combine(H, I, HS) ->
  L = 2*I,
  R = 2*I + 1,
  MP = I,
  MP_L = combine_h1(H, L, MP, HS),
  MP_R = combine_h1(H, R, MP_L, HS),
  combine_h2(H, MP_R, I, HS).
  
-spec combine_h1(heap(), pos_integer(), pos_integer(), pos_integer()) -> pos_integer().
  
combine_h1(H, W, MP, HS) when W =< HS ->
  [{W, {X, _RefX}}] = ets:lookup(H#heap.htab, W),
  [{MP, {Y, _RefY}}] = ets:lookup(H#heap.htab, MP),
  case {X > Y, H#heap.mode} of
    {'true',  'max'}  -> W;
    {'false', 'min'} -> W;
    {_, _} -> MP
  end;
combine_h1(_H, _W, MP, _HS) -> MP.

-spec combine_h2(heap(), pos_integer(), pos_integer(), pos_integer()) -> 'ok'.
  
combine_h2(_H, MP, I, _HS) when MP =:= I ->
  'ok';
combine_h2(H, MP, I, HS) ->
  swap(H, I, MP),
  combine(H, MP, HS).
  
-spec down_heapify(heap(), pos_integer(), term(), reference()) -> 'ok'.
  
down_heapify(H, I, X, Ref) ->
  ets:insert(H#heap.htab, {I, {X, Ref}}),
  HS = heap_size(H),
  combine(H, I, HS).
  
%% Swaps two elements of the heap
-spec swap(heap(), pos_integer(), pos_integer()) -> 'true'.

swap(H, I, J) ->
  [{I, {X, RX}}] = ets:lookup(H#heap.htab, I),
  [{J, {Y, RY}}] = ets:lookup(H#heap.htab, J),
  ets:insert(H#heap.htab, {I, {Y, RY}}),
  ets:insert(H#heap.htab, {RY, I}),
  ets:insert(H#heap.htab, {J, {X, RX}}),
  ets:insert(H#heap.htab, {RX, J}).
  
%% Used for constructing a heap from a list
-spec construct_heap(heap(), pos_integer(), pos_integer()) -> 'ok'.

construct_heap(H, I, HS) when I > 0 ->
  combine(H, I, HS),
  construct_heap(H, I-1, HS);
construct_heap(_H, _I, _HS) -> ok.
  
-spec ets_from_elements(mode(), [term()], non_neg_integer()) -> {heap(), [refterm()]}.
  
ets_from_elements(M, L, HS) ->
  H = new(M),
  ets:insert(H#heap.htab, {'size', HS}),
  Rs = add_elements(H, L, 1, []),
  {H, Rs}.
  
-spec add_elements(heap(), [term()], pos_integer(), [refterm()]) -> [refterm()].
  
add_elements(_H, [], _N, Acc) ->
  lists:reverse(Acc);
add_elements(H, [T|Ts], N, Acc) ->
  Ref = erlang:make_ref(),
  ets:insert(H#heap.htab, {N, {T, Ref}}),
  ets:insert(H#heap.htab, {Ref, N}),
  add_elements(H, Ts, N+1, [{T, Ref}|Acc]).
  

