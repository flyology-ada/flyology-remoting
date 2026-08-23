with Ada.Streams;
with Flyology.Buffers;
private with Flyology.Buffers.Channels;

--  Supplies a bounded in-process reference transport. One instance fixes the
--  capacity of every lane it creates. Payload handles transfer ownership
--  without copying bytes; received payloads expose no writable borrow.

generic
   Queue_Capacity : Positive;
package Flyology.Remoting.Transports.In_Process is

   --  One FIFO path from a sending endpoint to a receiving endpoint. Storage
   --  must outlive the lane and every payload associated with it.
   type Lane (Storage : not null access Flyology.Buffers.Pool) is limited private;

   --  Caller-owned mutable payload. A successful send leaves it vacant.
   type Writable_Payload (Storage : not null access Flyology.Buffers.Pool) is limited private;

   --  Receiver-owned immutable payload. Release returns its slot to Storage.
   type Received_Payload (Storage : not null access Flyology.Buffers.Pool) is limited private;

   --  Wait for one storage slot and attach it to a vacant payload.
   --  @param Item Payload that receives ownership
   procedure Acquire (Item : in out Writable_Payload)
   with Pre => not Has_Payload (Item), Post => Has_Payload (Item) and then Length (Item) = 0;

   --  Attempt to attach one storage slot without waiting.
   --  @param Item Payload that receives ownership on success
   --  @param Acquired True only when ownership was attached
   procedure Try_Acquire (Item : in out Writable_Payload; Acquired : out Boolean)
   with Pre => not Has_Payload (Item), Post => Acquired = Has_Payload (Item);

   --  Release a writable payload if it owns storage.
   --  @param Item Payload relinquishing ownership
   procedure Release (Item : in out Writable_Payload)
   with Post => not Has_Payload (Item);

   --  Release a received payload if it owns storage.
   --  @param Item Payload relinquishing ownership
   procedure Release (Item : in out Received_Payload)
   with Post => not Has_Payload (Item);

   --  Report whether a writable payload currently owns storage.
   --  @param Item Payload to inspect
   --  @return True only while Item owns a slot
   function Has_Payload (Item : Writable_Payload) return Boolean;

   --  Report whether a received payload currently owns storage.
   --  @param Item Payload to inspect
   --  @return True only while Item owns a slot
   function Has_Payload (Item : Received_Payload) return Boolean;

   --  Return the readable length of a writable payload, or zero when vacant.
   --  @param Item Payload to inspect
   --  @return Initialized byte count
   function Length (Item : Writable_Payload) return Natural;

   --  Return the readable length of a received payload, or zero when vacant.
   --  @param Item Payload to inspect
   --  @return Initialized byte count
   function Length (Item : Received_Payload) return Natural;

   --  Return the fixed storage capacity of a writable payload.
   --  @param Item Payload to inspect
   --  @return Maximum initialized byte count
   function Payload_Capacity (Item : Writable_Payload) return Positive;

   --  Borrow the full writable block for one callback. Length is committed
   --  only when Process returns normally with a value within capacity.
   --  @param Item Owned payload to modify
   --  @param Process Synchronous callback that must not retain Data
   procedure With_Writable_Data
     (Item    : in out Writable_Payload;
      Process :
        not null access procedure (Data : in out Ada.Streams.Stream_Element_Array; Length : in out Natural))
   with Pre => Has_Payload (Item);

   --  Borrow initialized writable-payload bytes for one callback.
   --  @param Item Owned payload to inspect
   --  @param Process Synchronous callback that must not retain Data
   procedure With_Readable_Data
     (Item : Writable_Payload; Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   with Pre => Has_Payload (Item);

   --  Borrow received bytes for one callback. The callback must not retain an
   --  address or reference derived from Data.
   --  @param Item Received payload to inspect
   --  @param Process Synchronous callback that must not retain Data
   procedure With_Readable_Data
     (Item : Received_Payload; Process : not null access procedure (Data : Ada.Streams.Stream_Element_Array))
   with Pre => Has_Payload (Item);

   --  Copy bytes into caller-owned payload storage. This convenience boundary
   --  is not the intended wire-codec path; codecs should use the writable
   --  callback directly.
   --  @param Item Owned destination payload
   --  @param Data Bytes to copy
   procedure Copy_From (Item : in out Writable_Payload; Data : Ada.Streams.Stream_Element_Array)
   with
     Pre  => Has_Payload (Item) and then Data'Length <= Payload_Capacity (Item),
     Post => Length (Item) = Data'Length;

   --  Attempt to append one payload without waiting. Acceptance transfers
   --  ownership to Item. Backpressure and closure preserve Value unchanged.
   --  @param Item Lane receiving the payload
   --  @param Value Caller-owned payload
   --  @param Result Transfer outcome
   procedure Try_Send
     (Item : in out Lane; Value : in out Writable_Payload; Result : out Try_Send_Result)
   with
     Pre  => Has_Payload (Value) and then Value.Storage = Item.Storage,
     Post => (Result = Message_Accepted) = (not Has_Payload (Value));

   --  Attempt to forward an immutable received payload without copying it.
   --  Acceptance transfers ownership to Item. Backpressure and closure
   --  preserve Value unchanged.
   --  @param Item Lane receiving the payload
   --  @param Value Receiver-owned payload to forward
   --  @param Result Transfer outcome
   procedure Try_Send
     (Item : in out Lane; Value : in out Received_Payload; Result : out Try_Send_Result)
   with
     Pre  => Has_Payload (Value) and then Value.Storage = Item.Storage,
     Post => (Result = Message_Accepted) = (not Has_Payload (Value));

   --  Attempt to receive the oldest accepted payload without waiting. Target
   --  remains vacant unless it receives sole ownership.
   --  @param Item Lane yielding a payload
   --  @param Target Vacant receiver handle
   --  @param Result Receive outcome
   procedure Try_Receive
     (Item : in out Lane; Target : in out Received_Payload; Result : out Try_Receive_Result)
   with
     Pre  => not Has_Payload (Target) and then Target.Storage = Item.Storage,
     Post => (Result = Message_Received) = Has_Payload (Target);

   --  Reject future sends while allowing accepted payloads to drain.
   --  @param Item Lane to close
   procedure Close (Item : in out Lane);

   --  Return one coherent lane snapshot.
   --  @param Item Lane to inspect
   --  @return Closed state and pending payload count
   function Current (Item : Lane) return Lane_Snapshot;

private
   type Lane (Storage : not null access Flyology.Buffers.Pool) is limited record
      Queue : Flyology.Buffers.Channels.Channel (Storage, Capacity => Queue_Capacity);
   end record;

   type Writable_Payload (Storage : not null access Flyology.Buffers.Pool) is limited record
      Buffer : Flyology.Buffers.Unique_Buffer (Storage);
   end record;

   type Received_Payload (Storage : not null access Flyology.Buffers.Pool) is limited record
      Buffer : Flyology.Buffers.Unique_Buffer (Storage);
   end record;

end Flyology.Remoting.Transports.In_Process;
