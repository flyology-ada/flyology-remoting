--  Nonblocking outcomes for local bounded-lane primitives. Session transports
--  wrap these outcomes with their distinct remote failure classifications.

package Flyology.Remoting.Transports
  with Preelaborate
is

   --  Result of attempting to transfer one payload to a transport.
   --  @enum Message_Accepted The transport took sole payload ownership
   --  @enum Backpressure Capacity is unavailable and the caller retains ownership
   --  @enum Send_Closed The lane no longer accepts messages and the caller retains ownership
   type Try_Send_Result is (Message_Accepted, Backpressure, Send_Closed);

   --  Result of attempting to receive one payload from a transport.
   --  @enum Message_Received The receiver obtained sole payload ownership
   --  @enum No_Message The open lane currently has no queued payload
   --  @enum Receive_Closed The closed lane has drained
   type Try_Receive_Result is (Message_Received, No_Message, Receive_Closed);

   --  Coherent state of one bounded unidirectional transport lane.
   --  @field Closed Whether the lane rejects new sends
   --  @field Pending Number of accepted payloads not yet received
   type Lane_Snapshot is record
      Closed  : Boolean;
      Pending : Natural;
   end record;

end Flyology.Remoting.Transports;
