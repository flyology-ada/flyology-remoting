with Flyology;
with Flyology.Remoting.Endpoints;
with Flyology.Remoting.Endpoints.Directories;
with Flyology.Remoting.Identities;

procedure Identity_Directory_Smoke is
   package Endpoints renames Flyology.Remoting.Endpoints;
   package Identities renames Flyology.Remoting.Identities;

   use type Endpoints.Endpoint_Generation;
   use type Endpoints.Endpoint_Reference;
   use type Endpoints.Endpoint_Slot;
   use type Identities.Identity_Word;
   use type Identities.Node_ID;
   use type Identities.Node_Reference;
   use type Identities.Session_ID;
   use type Identities.Session_Reference;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Assert;

   function Make_Node
     (Node_High, Node_Low, Incarnation_High, Incarnation_Low : Identities.Identity_Word)
      return Identities.Node_Reference is
     (Identities.Make_Node_Reference
        (Identities.Node_ID_From_Words (Node_High, Node_Low),
         Identities.Incarnation_ID_From_Words (Incarnation_High, Incarnation_Low)));

   procedure Run_Identity_Values is
      Node_ID       : constant Identities.Node_ID := Identities.Node_ID_From_Words (1, 2);
      Incarnation   : constant Identities.Incarnation_ID := Identities.Incarnation_ID_From_Words (3, 4);
      Session_ID    : constant Identities.Session_ID := Identities.Session_ID_From_Words (5, 6);
      First_Node    : constant Identities.Node_Reference :=
        Identities.Make_Node_Reference (Node_ID, Incarnation);
      Restarted     : constant Identities.Node_Reference :=
        Identities.Make_Node_Reference (Node_ID, Identities.Incarnation_ID_From_Words (3, 5));
      Second_Node   : constant Identities.Node_Reference := Make_Node (7, 8, 9, 10);
      First_Session : constant Identities.Session_Reference :=
        Identities.Make_Session_Reference (First_Node, Second_Node, Session_ID);
      Reconnected   : constant Identities.Session_Reference :=
        Identities.Make_Session_Reference
          (First_Node, Second_Node, Identities.Session_ID_From_Words (5, 7));
   begin
      Assert (not Identities.Is_Valid (Identities.No_Node_ID), "zero node ID was valid");
      Assert (not Identities.Is_Valid (Identities.No_Incarnation_ID), "zero incarnation was valid");
      Assert (not Identities.Is_Valid (Identities.No_Session_ID), "zero session ID was valid");
      Assert (not Identities.Is_Valid (Identities.No_Node), "empty node reference was valid");
      Assert (not Identities.Is_Valid (Identities.No_Session), "empty session reference was valid");
      Assert
        (not Identities.Is_Valid (Identities.Make_Node_Reference (Node_ID, Identities.No_Incarnation_ID)),
         "partially invalid node reference was valid");
      Assert
        (not Identities.Is_Valid
           (Identities.Make_Session_Reference (First_Node, Identities.No_Node, Session_ID)),
         "partially invalid session reference was valid");
      Assert (Identities.Is_Valid (Node_ID), "nonzero node ID was invalid");
      Assert (Identities.Is_Valid (Incarnation), "nonzero incarnation was invalid");
      Assert (Identities.Is_Valid (Session_ID), "nonzero session ID was invalid");
      Assert (Identities.High_Word (Node_ID) = 1, "node high word changed");
      Assert (Identities.Low_Word (Node_ID) = 2, "node low word changed");
      Assert (Identities.Is_Valid (First_Node), "complete node reference was invalid");
      Assert (Identities.Stable_ID (First_Node) = Identities.Stable_ID (Restarted), "stable ID changed");
      Assert (First_Node /= Restarted, "restart did not change node reference");
      Assert (Identities.Is_Valid (First_Session), "complete session reference was invalid");
      Assert (Identities.Initiator (First_Session) = First_Node, "session initiator changed");
      Assert (Identities.Acceptor (First_Session) = Second_Node, "session acceptor changed");
      Assert (Identities.Identity (First_Session) = Session_ID, "session identity changed");
      Assert (First_Session /= Reconnected, "reconnect reused a live-session reference");

      declare
         Slot       : constant Endpoints.Endpoint_Slot := Endpoints.Slot_From_Word (1);
         Generation : constant Endpoints.Endpoint_Generation := Endpoints.Generation_From_Word (1);
      begin
         Assert (Endpoints.To_Word (Slot) = 1, "endpoint slot word changed");
         Assert (Endpoints.To_Word (Generation) = 1, "endpoint generation word changed");
         Assert
           (not Endpoints.Is_Valid
              (Endpoints.Make_Endpoint_Reference
                 (First_Node, Endpoints.No_Endpoint_Slot, Generation)),
            "endpoint with invalid slot was valid");
         Assert
           (not Endpoints.Is_Valid
              (Endpoints.Make_Endpoint_Reference (First_Node, Slot, Endpoints.No_Endpoint_Generation)),
            "endpoint with invalid generation was valid");
      end;
   end Run_Identity_Values;

   procedure Run_Sequential_Directory is
      package Local_Directory is new Endpoints.Directories (Capacity => 2);

      use type Local_Directory.Claim_Result;
      use type Local_Directory.Directory_Snapshot;
      use type Local_Directory.Release_Result;

      Owner_Node   : constant Identities.Node_Reference := Make_Node (11, 12, 13, 14);
      Restarted    : constant Identities.Node_Reference := Make_Node (11, 12, 13, 15);
      Foreign      : constant Identities.Node_Reference := Make_Node (21, 22, 23, 24);
      Directory    : Local_Directory.Directory := Local_Directory.Create (Owner_Node);
      First        : Endpoints.Endpoint_Reference;
      Second       : Endpoints.Endpoint_Reference;
      Replacement  : Endpoints.Endpoint_Reference;
      Failed       : Endpoints.Endpoint_Reference;
      Forged       : Endpoints.Endpoint_Reference;
      Claim        : Local_Directory.Claim_Result;
      Release      : Local_Directory.Release_Result;
      Rejected_Invalid_Owner : Boolean := False;
   begin
      begin
         declare
            Invalid : constant Local_Directory.Directory :=
              Local_Directory.Create (Identities.No_Node);
         begin
            Assert
              (Local_Directory.Owner (Invalid) = Identities.No_Node,
               "invalid directory construction unexpectedly returned");
         end;
      exception
         when Local_Directory.Invalid_Owner =>
            Rejected_Invalid_Owner := True;
      end;
      Assert (Rejected_Invalid_Owner, "invalid directory owner was accepted");

      Local_Directory.Try_Claim (Directory, First, Claim);
      Assert (Claim = Local_Directory.Endpoint_Claimed, "first endpoint claim failed");
      Local_Directory.Try_Claim (Directory, Second, Claim);
      Assert (Claim = Local_Directory.Endpoint_Claimed, "second endpoint claim failed");
      Assert (First /= Second, "distinct claims returned one endpoint reference");
      Assert (Local_Directory.Is_Current (Directory, First), "first claim was not current");
      Assert
        (Local_Directory.Current (Directory) = (Active => 2, Available => 0, Exhausted => 0),
         "full directory snapshot was wrong");

      Local_Directory.Try_Claim (Directory, Failed, Claim);
      Assert
        (Claim = Local_Directory.Directory_Full and then Failed = Endpoints.No_Endpoint,
         "full directory returned an endpoint");

      Local_Directory.Release (Directory, First, Release);
      Assert (Release = Local_Directory.Released, "current endpoint release failed");
      Local_Directory.Try_Claim (Directory, Replacement, Claim);
      Assert (Claim = Local_Directory.Endpoint_Claimed, "released slot was not reusable");
      Assert (Endpoints.Slot (Replacement) = Endpoints.Slot (First), "claim did not reuse free slot");
      Assert
        (Endpoints.Generation (Replacement) /= Endpoints.Generation (First),
         "slot reuse did not advance generation");
      Assert (not Local_Directory.Is_Current (Directory, First), "stale generation remained current");

      Local_Directory.Release (Directory, First, Release);
      Assert (Release = Local_Directory.Stale_Endpoint, "stale generation release was accepted");

      Forged :=
        Endpoints.Make_Endpoint_Reference
          (Restarted, Endpoints.Slot (Replacement), Endpoints.Generation (Replacement));
      Local_Directory.Release (Directory, Forged, Release);
      Assert (Release = Local_Directory.Stale_Incarnation, "stale incarnation was not distinguished");

      Forged :=
        Endpoints.Make_Endpoint_Reference
          (Foreign, Endpoints.Slot (Replacement), Endpoints.Generation (Replacement));
      Local_Directory.Release (Directory, Forged, Release);
      Assert (Release = Local_Directory.Foreign_Node, "foreign node was not distinguished");
      Assert (Local_Directory.Is_Current (Directory, Replacement), "forged release changed ownership");

      Local_Directory.Release (Directory, Second, Release);
      Assert (Release = Local_Directory.Released, "second endpoint release failed");
      Local_Directory.Release (Directory, Replacement, Release);
      Assert (Release = Local_Directory.Released, "replacement endpoint release failed");
      Assert
        (Local_Directory.Current (Directory) = (Active => 0, Available => 2, Exhausted => 0),
         "drained directory snapshot was wrong");
   end Run_Sequential_Directory;

   procedure Run_Concurrent_Directory is
      Directory_Capacity : constant Positive := 8;
      Claimer_Count      : constant Positive := 12;

      package Concurrent_Directory is new Endpoints.Directories (Capacity => Directory_Capacity);

      use type Concurrent_Directory.Claim_Result;
      use type Concurrent_Directory.Directory_Snapshot;
      use type Concurrent_Directory.Release_Result;

      Owner_Node : constant Identities.Node_Reference := Make_Node (31, 32, 33, 34);
      Directory  : Concurrent_Directory.Directory := Concurrent_Directory.Create (Owner_Node);

      type Reference_Array is array (Positive range <>) of Endpoints.Endpoint_Reference;

      protected Results is
         procedure Publish
           (Reference : Endpoints.Endpoint_Reference; Result : Concurrent_Directory.Claim_Result);
         procedure Record_Failure;
         entry Wait
           (Succeeded : out Natural; Rejected : out Natural; Duplicate : out Boolean; Failed : out Natural);
         function Reference_At (Index : Positive) return Endpoints.Endpoint_Reference;
      private
         Stored        : Reference_Array (1 .. Directory_Capacity) := (others => Endpoints.No_Endpoint);
         Success_Count : Natural := 0;
         Reject_Count  : Natural := 0;
         Failure_Count : Natural := 0;
         Complete_Count : Natural := 0;
         Has_Duplicate : Boolean := False;
      end Results;

      protected body Results is
         procedure Publish
           (Reference : Endpoints.Endpoint_Reference; Result : Concurrent_Directory.Claim_Result)
         is
         begin
            if Result = Concurrent_Directory.Endpoint_Claimed then
               if not Endpoints.Is_Valid (Reference) or else Success_Count = Directory_Capacity then
                  Failure_Count := Failure_Count + 1;
               else
                  for Index in 1 .. Success_Count loop
                     Has_Duplicate := Has_Duplicate or else Stored (Index) = Reference;
                  end loop;
                  Success_Count := Success_Count + 1;
                  Stored (Success_Count) := Reference;
               end if;
            elsif Endpoints.Is_Valid (Reference) then
               Failure_Count := Failure_Count + 1;
            else
               Reject_Count := Reject_Count + 1;
            end if;
            Complete_Count := Complete_Count + 1;
         end Publish;

         procedure Record_Failure is
         begin
            Failure_Count := Failure_Count + 1;
            Complete_Count := Complete_Count + 1;
         end Record_Failure;

         entry Wait
           (Succeeded : out Natural; Rejected : out Natural; Duplicate : out Boolean; Failed : out Natural)
           when Complete_Count = Claimer_Count
         is
         begin
            Succeeded := Success_Count;
            Rejected := Reject_Count;
            Duplicate := Has_Duplicate;
            Failed := Failure_Count;
         end Wait;

         function Reference_At (Index : Positive) return Endpoints.Endpoint_Reference is
           (Stored (Index));
      end Results;

      task type Claimer is
         pragma Task_Info (Flyology.Lightweight_Task);
      end Claimer;

      task body Claimer is
         Reference : Endpoints.Endpoint_Reference;
         Result    : Concurrent_Directory.Claim_Result;
      begin
         Concurrent_Directory.Try_Claim (Directory, Reference, Result);
         Results.Publish (Reference, Result);
      exception
         when others =>
            Results.Record_Failure;
      end Claimer;

      Workers    : array (1 .. Claimer_Count) of Claimer;
      Succeeded  : Natural;
      Rejected   : Natural;
      Failed     : Natural;
      Duplicate  : Boolean;
      Release    : Concurrent_Directory.Release_Result;
   begin
      Results.Wait (Succeeded, Rejected, Duplicate, Failed);
      Assert (Succeeded = Directory_Capacity, "concurrent claims lost available slots");
      Assert (Rejected = Claimer_Count - Directory_Capacity, "concurrent capacity result was wrong");
      Assert (Failed = 0, "concurrent claim raised or returned an inconsistent result");
      Assert (not Duplicate, "concurrent claims duplicated an endpoint reference");
      Assert
        (Concurrent_Directory.Current (Directory) =
           (Active => Directory_Capacity, Available => 0, Exhausted => 0),
         "concurrent directory snapshot was wrong");

      for Index in 1 .. Directory_Capacity loop
         Concurrent_Directory.Release (Directory, Results.Reference_At (Index), Release);
         Assert (Release = Concurrent_Directory.Released, "concurrent endpoint release failed");
      end loop;

      Assert
        (Concurrent_Directory.Current (Directory) =
           (Active => 0, Available => Directory_Capacity, Exhausted => 0),
         "concurrent directory did not drain");
   end Run_Concurrent_Directory;
begin
   Run_Identity_Values;
   Run_Sequential_Directory;
   Run_Concurrent_Directory;
end Identity_Directory_Smoke;
