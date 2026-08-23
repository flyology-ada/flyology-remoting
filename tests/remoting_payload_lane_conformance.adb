package body Remoting_Payload_Lane_Conformance is
   package Transports renames Flyology.Remoting.Transports;

   use type Ada.Streams.Stream_Element_Array;
   use type Transports.Lane_Snapshot;
   use type Transports.Try_Receive_Result;
   use type Transports.Try_Send_Result;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Assert;

   procedure Run is
      Source      : Lane := Create_Lane;
      Destination : Lane := Create_Lane;
      First       : Writable_Payload := Create_Writable;
      Second      : Writable_Payload := Create_Writable;
      Overflow    : Writable_Payload := Create_Writable;
      After_Close : Writable_Payload := Create_Writable;
      Inbound     : Received_Payload := Create_Received;
      Relay       : Received_Payload := Create_Received;
      Send_Result : Transports.Try_Send_Result;
      Receive_Result : Transports.Try_Receive_Result;

      procedure Expect
        (Item : Received_Payload; Expected : Ada.Streams.Stream_Element_Array; Message : String)
      is
         Matches : Boolean := False;

         procedure Check (Data : Ada.Streams.Stream_Element_Array) is
         begin
            Matches := Data = Expected;
         end Check;
      begin
         Read_Received (Item, Check'Access);
         Assert (Matches, Message);
      end Expect;

      procedure Expect_Writable
        (Item : Writable_Payload; Expected : Ada.Streams.Stream_Element_Array; Message : String)
      is
         Matches : Boolean := False;

         procedure Check (Data : Ada.Streams.Stream_Element_Array) is
         begin
            Matches := Data = Expected;
         end Check;
      begin
         Read_Writable (Item, Check'Access);
         Assert (Matches, Message);
      end Expect_Writable;
   begin
      Assert (Lane_Capacity = 2, "payload-lane conformance requires exactly two queue slots");
      Assert
        (Current (Source) = (Closed => False, Pending => 0),
         "new lane did not start open and empty");

      Acquire (First);
      Assert
        (Has_Writable (First) and then Length_Writable (First) = 0,
         "acquire did not yield empty payload");
      Copy_From (First, [11]);
      Try_Send_Writable (Source, First, Send_Result);
      Assert
        (Send_Result = Transports.Message_Accepted and then not Has_Writable (First),
         "first accepted send retained caller ownership");

      Acquire (Second);
      Copy_From (Second, [12]);
      Try_Send_Writable (Source, Second, Send_Result);
      Assert
        (Send_Result = Transports.Message_Accepted and then not Has_Writable (Second),
         "second queue slot was not accepted with ownership transfer");
      Assert
        (Current (Source) = (Closed => False, Pending => 2),
         "full lane snapshot did not report its bounded pending count");

      Acquire (Overflow);
      Copy_From (Overflow, [13]);
      Try_Send_Writable (Source, Overflow, Send_Result);
      Assert
        (Send_Result = Transports.Backpressure and then Has_Writable (Overflow),
         "backpressure consumed caller ownership");

      Try_Receive (Source, Inbound, Receive_Result);
      Assert
        (Receive_Result = Transports.Message_Received and then Has_Received (Inbound),
         "receive did not transfer sole ownership");
      Expect (Inbound, [11], "first accepted payload was reordered or changed");
      Release_Received (Inbound);

      Try_Send_Writable (Source, Overflow, Send_Result);
      Assert
        (Send_Result = Transports.Message_Accepted and then not Has_Writable (Overflow),
         "send after capacity release did not transfer ownership");

      Try_Receive (Source, Inbound, Receive_Result);
      Assert (Receive_Result = Transports.Message_Received, "second accepted payload was unavailable");
      Expect (Inbound, [12], "second accepted payload was reordered or changed");
      Release_Received (Inbound);

      Try_Receive (Source, Inbound, Receive_Result);
      Assert (Receive_Result = Transports.Message_Received, "post-backpressure payload was unavailable");
      Expect (Inbound, [13], "post-backpressure payload was reordered or changed");
      Release_Received (Inbound);

      Try_Receive (Source, Inbound, Receive_Result);
      Assert
        (Receive_Result = Transports.No_Message and then not Has_Received (Inbound),
         "open drained lane did not preserve vacant receive ownership");

      Acquire (First);
      Assert (Length_Writable (First) = 0, "reacquired payload did not reset its length");
      Try_Send_Writable (Destination, First, Send_Result);
      Assert
        (Send_Result = Transports.Message_Accepted and then not Has_Writable (First),
         "empty payload send did not transfer ownership");
      Try_Receive (Destination, Inbound, Receive_Result);
      Assert
        (Receive_Result = Transports.Message_Received and then Length_Received (Inbound) = 0,
         "empty payload did not survive transfer");
      Release_Received (Inbound);

      Acquire (First);
      Copy_From (First, [41]);
      Try_Send_Writable (Destination, First, Send_Result);
      Assert (Send_Result = Transports.Message_Accepted, "first forwarding barrier send was rejected");
      Acquire (Second);
      Copy_From (Second, [42]);
      Try_Send_Writable (Destination, Second, Send_Result);
      Assert (Send_Result = Transports.Message_Accepted, "second forwarding barrier send was rejected");

      Acquire (Overflow);
      Copy_From (Overflow, [21, 22]);
      Try_Send_Writable (Source, Overflow, Send_Result);
      Assert (Send_Result = Transports.Message_Accepted, "forwarding setup send was rejected");
      Try_Receive (Source, Relay, Receive_Result);
      Assert
        (Receive_Result = Transports.Message_Received and then Has_Received (Relay),
         "forwarding setup receive did not transfer ownership");
      Try_Send_Received (Destination, Relay, Send_Result);
      Assert
        (Send_Result = Transports.Backpressure and then Has_Received (Relay),
         "forwarding backpressure consumed receiver ownership");
      Expect (Relay, [21, 22], "forwarding backpressure changed the payload");

      Try_Receive (Destination, Inbound, Receive_Result);
      Assert (Receive_Result = Transports.Message_Received, "first forwarding barrier was unavailable");
      Expect (Inbound, [41], "first forwarding barrier changed");
      Release_Received (Inbound);

      Try_Send_Received (Destination, Relay, Send_Result);
      Assert
        (Send_Result = Transports.Message_Accepted and then not Has_Received (Relay),
         "forwarding retry retained receiver ownership");
      Try_Receive (Destination, Inbound, Receive_Result);
      Assert (Receive_Result = Transports.Message_Received, "second forwarding barrier was unavailable");
      Expect (Inbound, [42], "second forwarding barrier changed");
      Release_Received (Inbound);
      Try_Receive (Destination, Inbound, Receive_Result);
      Assert (Receive_Result = Transports.Message_Received, "forwarded payload was unavailable");
      Expect (Inbound, [21, 22], "forwarded payload changed");
      Release_Received (Inbound);

      Acquire (First);
      Copy_From (First, [23]);
      Try_Send_Writable (Source, First, Send_Result);
      Assert (Send_Result = Transports.Message_Accepted, "closed-forward setup send was rejected");
      Try_Receive (Source, Relay, Receive_Result);
      Assert (Receive_Result = Transports.Message_Received, "closed-forward setup receive failed");
      Close (Destination);
      Try_Send_Received (Destination, Relay, Send_Result);
      Assert
        (Send_Result = Transports.Send_Closed and then Has_Received (Relay),
         "closed forwarding consumed receiver ownership");
      Expect (Relay, [23], "closed forwarding changed the payload");
      Release_Received (Relay);

      Acquire (First);
      Copy_From (First, [31]);
      Try_Send_Writable (Source, First, Send_Result);
      Assert
        (Send_Result = Transports.Message_Accepted and then not Has_Writable (First),
         "close/drain setup send did not transfer ownership");
      Close (Source);
      Assert
        (Current (Source) = (Closed => True, Pending => 1),
         "closed lane snapshot did not retain accepted payload");

      Acquire (After_Close);
      Copy_From (After_Close, [32]);
      Try_Send_Writable (Source, After_Close, Send_Result);
      Assert
        (Send_Result = Transports.Send_Closed and then Has_Writable (After_Close),
         "closed send consumed caller ownership");
      Expect_Writable (After_Close, [32], "closed send changed the caller payload");

      Try_Receive (Source, Inbound, Receive_Result);
      Assert (Receive_Result = Transports.Message_Received, "close discarded accepted payload");
      Expect (Inbound, [31], "close/drain payload changed");
      Release_Received (Inbound);
      Try_Receive (Source, Inbound, Receive_Result);
      Assert
        (Receive_Result = Transports.Receive_Closed and then not Has_Received (Inbound),
         "closed drained lane did not preserve vacant receive ownership");
      Release_Writable (After_Close);

      Try_Receive (Destination, Inbound, Receive_Result);
      Assert
        (Receive_Result = Transports.Receive_Closed and then not Has_Received (Inbound),
         "empty closed lane did not preserve vacant receive ownership");
      Assert (Resources_Balanced, "payload resource ownership did not return to its initial balance");
   end Run;

end Remoting_Payload_Lane_Conformance;
