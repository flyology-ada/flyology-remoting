package body Remoting_Local_Node_Conformance is
   package Endpoints renames Flyology.Remoting.Endpoints;
   package Identities renames Flyology.Remoting.Identities;
   package Nodes renames Flyology.Remoting.Nodes;

   use type Ada.Streams.Stream_Element_Array;
   use type Endpoints.Endpoint_Generation;
   use type Endpoints.Endpoint_Slot;
   use type Identities.Node_Reference;
   use type Nodes.Claim_Result;
   use type Nodes.Close_Result;
   use type Nodes.Node_Snapshot;
   use type Nodes.Try_Receive_Result;
   use type Nodes.Try_Send_Result;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Assert;

   function Node_Identity
     (Node_High, Node_Low, Incarnation_High, Incarnation_Low : Identities.Identity_Word)
      return Identities.Node_Reference
   is
     (Identities.Make_Node_Reference
        (Identities.Node_ID_From_Words (Node_High, Node_Low),
         Identities.Incarnation_ID_From_Words (Incarnation_High, Incarnation_Low)));

   procedure Run is
      Owner          : constant Identities.Node_Reference := Node_Identity (1, 2, 3, 4);
      Other_Node     : constant Identities.Node_Reference := Node_Identity (5, 6, 7, 8);
      Other_Lifetime : constant Identities.Node_Reference := Node_Identity (1, 2, 9, 10);
      Server         : aliased Local_Node := Create_Node (Owner);
      Endpoint_Owner : Endpoint_Handle := Claim (Server'Access);
      Full_Owner     : constant Endpoint_Handle := Claim (Server'Access);
      Endpoint       : Endpoints.Endpoint_Reference := Endpoints.No_Endpoint;
      Foreign        : Endpoints.Endpoint_Reference := Endpoints.No_Endpoint;
      Old_Lifetime   : Endpoints.Endpoint_Reference := Endpoints.No_Endpoint;
      First          : Writable_Payload := Create_Writable;
      Second         : Writable_Payload := Create_Writable;
      Third          : Writable_Payload := Create_Writable;
      Inbound        : Received_Payload := Create_Received;
      Relay          : Received_Payload := Create_Received;
      Send_Result    : Nodes.Try_Send_Result;
      Receive_Result : Nodes.Try_Receive_Result;
      Close_Result   : Nodes.Close_Result;

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

      procedure Expect_Received
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
      end Expect_Received;
   begin
      Assert
        (Endpoint_Capacity = 1 and then Mailbox_Capacity = 2,
         "local-node conformance requires one endpoint and two mailbox slots");

      declare
         Invalid_Rejected : Boolean := False;
         Constructor_Returned : Boolean := False;
      begin
         begin
            declare
               Invalid : constant Local_Node := Create_Node (Identities.No_Node);
            begin
               Constructor_Returned := True;
               Assert
                 (Node_Owner (Invalid) = Identities.No_Node,
                  "invalid node constructor returned a different owner");
            end;
         exception
            when Nodes.Invalid_Owner =>
               Invalid_Rejected := not Constructor_Returned;
         end;
         Assert (Invalid_Rejected, "invalid node owner was accepted or rejected after construction");
      end;

      Assert (Node_Owner (Server) = Owner, "local node changed its exact owner incarnation");
      Assert (Claim_Status (Endpoint_Owner) = Nodes.Endpoint_Claimed, "endpoint claim failed");
      Assert
        (Claim_Status (Full_Owner) = Nodes.Directory_Full and then not Has_Endpoint (Full_Owner),
         "bounded claim exhaustion returned an endpoint or the wrong status");
      Endpoint := Reference (Endpoint_Owner);
      Assert
        (Endpoints.Destination_Node (Endpoint) = Owner and then Is_Current (Server, Endpoint),
         "claimed endpoint has the wrong owner or is not current");
      Assert
        (Current (Server) = (Active => 1, Closing => 0, Available => 0, Exhausted => 0),
         "claimed-node snapshot is incoherent");

      Acquire (First);
      Copy_From (First, [11]);
      Try_Send_Writable (Server, Endpoint, First, Send_Result);
      Assert
        (Send_Result = Nodes.Message_Accepted and then not Has_Writable (First),
         "accepted node send retained caller ownership");

      Acquire (Second);
      Copy_From (Second, [12]);
      Try_Send_Writable (Server, Endpoint, Second, Send_Result);
      Assert
        (Send_Result = Nodes.Message_Accepted and then not Has_Writable (Second),
         "second accepted node send retained caller ownership");

      Acquire (Third);
      Copy_From (Third, [14]);
      Try_Send_Writable (Server, Endpoint, Third, Send_Result);
      Assert
        (Send_Result = Nodes.Backpressure and then Has_Writable (Third),
         "node backpressure consumed caller ownership");
      Expect_Writable (Third, [14], "node backpressure changed caller bytes");

      Try_Receive (Server, Endpoint, Inbound, Receive_Result);
      Assert
        (Receive_Result = Nodes.Message_Received and then Has_Received (Inbound),
         "node receive did not transfer first ownership");
      Expect_Received (Inbound, [11], "node routing reordered or changed the first accepted payload");
      Release_Received (Inbound);
      Try_Receive (Server, Endpoint, Inbound, Receive_Result);
      Assert
        (Receive_Result = Nodes.Message_Received and then Has_Received (Inbound),
         "node receive did not transfer second ownership");
      Expect_Received (Inbound, [12], "node routing reordered or changed the second accepted payload");
      Release_Received (Inbound);
      Try_Receive (Server, Endpoint, Inbound, Receive_Result);
      Assert
        (Receive_Result = Nodes.No_Message and then not Has_Received (Inbound),
         "empty current endpoint changed receive ownership");

      Copy_From (Third, [14]);

      Foreign :=
        Endpoints.Make_Endpoint_Reference
          (Other_Node, Endpoints.Slot (Endpoint), Endpoints.Generation (Endpoint));
      Old_Lifetime :=
        Endpoints.Make_Endpoint_Reference
          (Other_Lifetime, Endpoints.Slot (Endpoint), Endpoints.Generation (Endpoint));

      Try_Send_Writable (Server, Foreign, Third, Send_Result);
      Assert
        (Send_Result = Nodes.Foreign_Node and then Has_Writable (Third),
         "foreign-node rejection consumed writable ownership");
      Try_Send_Writable (Server, Old_Lifetime, Third, Send_Result);
      Assert
        (Send_Result = Nodes.Stale_Incarnation and then Has_Writable (Third),
         "stale-incarnation rejection consumed writable ownership");
      Try_Send_Writable (Server, Endpoints.No_Endpoint, Third, Send_Result);
      Assert
        (Send_Result = Nodes.Stale_Endpoint and then Has_Writable (Third),
         "invalid-endpoint rejection consumed writable ownership");
      Expect_Writable (Third, [14], "routing rejection changed writable bytes");

      Try_Send_Writable (Server, Endpoint, Third, Send_Result);
      Assert
        (Send_Result = Nodes.Message_Accepted and then not Has_Writable (Third),
         "receive-rejection setup send failed or retained ownership");

      Try_Receive (Server, Foreign, Inbound, Receive_Result);
      Assert
        (Receive_Result = Nodes.Foreign_Node and then not Has_Received (Inbound),
         "foreign-node receive rejection changed target ownership");
      Try_Receive (Server, Old_Lifetime, Inbound, Receive_Result);
      Assert
        (Receive_Result = Nodes.Stale_Incarnation and then not Has_Received (Inbound),
         "stale-incarnation receive rejection changed target ownership");
      Try_Receive (Server, Endpoints.No_Endpoint, Inbound, Receive_Result);
      Assert
        (Receive_Result = Nodes.Stale_Endpoint and then not Has_Received (Inbound),
         "invalid-endpoint receive rejection changed target ownership");

      Try_Receive (Server, Endpoint, Relay, Receive_Result);
      Assert
        (Receive_Result = Nodes.Message_Received and then Has_Received (Relay),
         "forwarding setup receive failed");
      Expect_Received (Relay, [14], "rejected receive changed or discarded the queued payload");
      Try_Send_Received (Server, Foreign, Relay, Send_Result);
      Assert
        (Send_Result = Nodes.Foreign_Node and then Has_Received (Relay),
         "foreign forwarding rejection consumed received ownership");
      Try_Send_Received (Server, Old_Lifetime, Relay, Send_Result);
      Assert
        (Send_Result = Nodes.Stale_Incarnation and then Has_Received (Relay),
         "stale-incarnation forwarding consumed received ownership");
      Expect_Received (Relay, [14], "forwarding rejection changed received bytes");

      Acquire (First);
      Copy_From (First, [31]);
      Try_Send_Writable (Server, Endpoint, First, Send_Result);
      Assert
        (Send_Result = Nodes.Message_Accepted and then not Has_Writable (First),
         "first forwarding barrier send failed or retained ownership");
      Acquire (Second);
      Copy_From (Second, [32]);
      Try_Send_Writable (Server, Endpoint, Second, Send_Result);
      Assert
        (Send_Result = Nodes.Message_Accepted and then not Has_Writable (Second),
         "second forwarding barrier send failed or retained ownership");
      Try_Send_Received (Server, Endpoint, Relay, Send_Result);
      Assert
        (Send_Result = Nodes.Backpressure and then Has_Received (Relay),
         "forwarding backpressure consumed received ownership");
      Expect_Received (Relay, [14], "forwarding backpressure changed received bytes");

      Try_Receive (Server, Endpoint, Inbound, Receive_Result);
      Assert (Receive_Result = Nodes.Message_Received, "first forwarding barrier was unavailable");
      Expect_Received (Inbound, [31], "first forwarding barrier changed");
      Release_Received (Inbound);
      Try_Send_Received (Server, Endpoint, Relay, Send_Result);
      Assert
        (Send_Result = Nodes.Message_Accepted and then not Has_Received (Relay),
         "forwarding retry retained receiver ownership");
      Try_Receive (Server, Endpoint, Inbound, Receive_Result);
      Assert (Receive_Result = Nodes.Message_Received, "second forwarding barrier was unavailable");
      Expect_Received (Inbound, [32], "second forwarding barrier changed");
      Release_Received (Inbound);
      Try_Receive (Server, Endpoint, Inbound, Receive_Result);
      Assert (Receive_Result = Nodes.Message_Received, "forwarded payload was unavailable after retry");
      Expect_Received (Inbound, [14], "forwarded payload changed");
      Release_Received (Inbound);

      Acquire (First);
      Copy_From (First, [21]);
      Try_Send_Writable (Server, Endpoint, First, Send_Result);
      Assert
        (Send_Result = Nodes.Message_Accepted and then not Has_Writable (First),
         "close/drain setup send was rejected or retained ownership");
      Close (Endpoint_Owner, Close_Result);
      Assert
        (Close_Result = Nodes.Endpoint_Closed
         and then not Has_Endpoint (Endpoint_Owner)
         and then Claim_Status (Endpoint_Owner) = Nodes.Endpoint_Claimed
         and then not Is_Current (Server, Endpoint),
         "endpoint close did not preserve its claim result or retire its exact generation");
      Assert
        (Current (Server) = (Active => 0, Closing => 0, Available => 1, Exhausted => 0),
         "closed-node snapshot is incoherent");
      Assert (Resources_Balanced, "endpoint close did not drain accepted payload ownership");
      Close (Endpoint_Owner, Close_Result);
      Assert (Close_Result = Nodes.Endpoint_Closed, "explicit endpoint close is not idempotent");

      Acquire (Third);
      Copy_From (Third, [22]);
      Try_Send_Writable (Server, Endpoint, Third, Send_Result);
      Assert
        (Send_Result = Nodes.Stale_Endpoint and then Has_Writable (Third),
         "retired endpoint send was accepted or consumed");
      Expect_Writable (Third, [22], "retired endpoint rejection changed writable bytes");
      Try_Receive (Server, Endpoint, Inbound, Receive_Result);
      Assert
        (Receive_Result = Nodes.Stale_Endpoint and then not Has_Received (Inbound),
         "retired endpoint receive changed target ownership");

      declare
         Replacement_Owner : Endpoint_Handle := Claim (Server'Access);
         Replacement       : Endpoints.Endpoint_Reference := Endpoints.No_Endpoint;
      begin
         Assert
           (Claim_Status (Replacement_Owner) = Nodes.Endpoint_Claimed,
            "node did not reclaim its retired endpoint slot");
         Replacement := Reference (Replacement_Owner);
         Assert
           (Endpoints.Slot (Replacement) = Endpoints.Slot (Endpoint)
            and then Endpoints.Generation (Replacement) /= Endpoints.Generation (Endpoint)
            and then Is_Current (Server, Replacement)
            and then not Is_Current (Server, Endpoint),
            "slot reuse did not advance and isolate the endpoint generation");

         Try_Send_Writable (Server, Replacement, Third, Send_Result);
         Assert
           (Send_Result = Nodes.Message_Accepted and then not Has_Writable (Third),
            "replacement endpoint rejected a send or retained ownership");
         Try_Receive (Server, Replacement, Relay, Receive_Result);
         Assert (Receive_Result = Nodes.Message_Received, "replacement endpoint receive failed");
         Try_Send_Received (Server, Endpoint, Relay, Send_Result);
         Assert
           (Send_Result = Nodes.Stale_Endpoint and then Has_Received (Relay),
            "stale-generation forwarding consumed received ownership");
         Expect_Received (Relay, [22], "stale-generation forwarding changed received bytes");
         Try_Send_Received (Server, Replacement, Relay, Send_Result);
         Assert
           (Send_Result = Nodes.Message_Accepted and then not Has_Received (Relay),
            "replacement forwarding retry failed or retained ownership");
         Try_Receive (Server, Replacement, Inbound, Receive_Result);
         Assert (Receive_Result = Nodes.Message_Received, "replacement forwarded receive failed");
         Expect_Received (Inbound, [22], "replacement forwarding changed payload bytes");
         Release_Received (Inbound);
         Close (Replacement_Owner, Close_Result);
         Assert (Close_Result = Nodes.Endpoint_Closed, "replacement endpoint close failed");
      end;

      Assert (Resources_Balanced, "local-node conformance leaked payload ownership");
   end Run;

end Remoting_Local_Node_Conformance;
