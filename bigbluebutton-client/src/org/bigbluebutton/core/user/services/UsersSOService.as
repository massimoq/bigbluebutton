/**
 * BigBlueButton open source conferencing system - http://www.bigbluebutton.org/
 *
 * Copyright (c) 2010 BigBlueButton Inc. and by respective authors (see below).
 *
 * This program is free software; you can redistribute it and/or modify it under the
 * terms of the GNU Lesser General Public License as published by the Free Software
 * Foundation; either version 2.1 of the License, or (at your option) any later
 * version.
 *
 * BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
 * PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License along
 * with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.
 * 
 */
package org.bigbluebutton.core.user.services {
  import com.asfusion.mate.events.Dispatcher;
  
  import flash.events.AsyncErrorEvent;
  import flash.events.IEventDispatcher;
  import flash.events.NetStatusEvent;
  import flash.net.NetConnection;
  import flash.net.Responder;
  import flash.net.SharedObject;
  
  import mx.collections.ArrayCollection;
  
  import org.bigbluebutton.common.LogUtil;
  import org.bigbluebutton.core.BBB;
  import org.bigbluebutton.core.managers.ConnectionManager;
  import org.bigbluebutton.core.managers.UserManager;
  import org.bigbluebutton.core.user.events.UserEvent;
  import org.bigbluebutton.core.user.model.MeetingModel;
  import org.bigbluebutton.core.user.model.UsersModel;
  import org.bigbluebutton.core.user.model.vo.Status;
  import org.bigbluebutton.core.user.model.vo.User;
  import org.bigbluebutton.main.events.BBBEvent;
  import org.bigbluebutton.main.events.LogoutEvent;
  import org.bigbluebutton.main.events.MadePresenterEvent;
  import org.bigbluebutton.main.events.ParticipantJoinEvent;
  import org.bigbluebutton.main.events.PresenterStatusEvent;
  import org.bigbluebutton.main.model.ConferenceParameters;
  import org.bigbluebutton.main.model.users.events.ConnectionFailedEvent;
  import org.bigbluebutton.main.model.users.events.RoleChangeEvent;
  
  public class UsersSOService {    
    public var dispatcher:IEventDispatcher;
    public var connService:ConnectionService;
    public var meetingModel:MeetingModel;
    public var usersModel:UsersModel;
    
    private var _participantsSO:SharedObject;
    private static const SO_NAME : String = "participantsSO";
        
    public function disconnect(onUserAction:Boolean):void {
      if (_participantsSO != null) _participantsSO.close();
      connService.disconnect(onUserAction);
    }
    
    public function queryForUsers():void {
      _participantsSO = SharedObject.getRemote(SO_NAME, connService.connectionUri, false);
      _participantsSO.addEventListener(NetStatusEvent.NET_STATUS, netStatusHandler);
      _participantsSO.addEventListener(AsyncErrorEvent.ASYNC_ERROR, asyncErrorHandler);
      _participantsSO.client = this;
      _participantsSO.connect(connService.connection);
      sendQueryForParticipants();					     
    }
    
    private function sendQueryForParticipants():void {
      var nc:NetConnection = connService.connection;
      nc.call(
        "participants.getParticipants",// Remote function name
        new Responder(
          // participants - On successful result
          function(result:Object):void { 
            LogUtil.debug("Successfully queried participants: " + result.count); 
            if (result.count > 0) {
              var users:ArrayCollection = new ArrayCollection();
              
              for(var p:Object in result.participants) {
                var usr:Object = result.participants[p] as Object;
//                participantJoined(usr);
                var user:User = new User();
                var userIDTemp:Number = Number(usr.userid);
                user.userid = userIDTemp.toString();
                user.name = usr.name;
                user.role = usr.role;
                user.changeStatus(new Status("hasStream", usr.status.hasStream));
                user.changeStatus(new Status("presenter", usr.status.presenter));
                user.changeStatus(new Status("raiseHand", usr.status.raiseHand));
                LogUtil.info("Joined as [" + user.userid + "," + user.name + "," + user.role + "]");
                users.addItem(user);
              }
            }	
            
            usersModel.addUsers(users);
            
            dispatcher.dispatchEvent(new UserEvent(UserEvent.USERS_ADDED));
          },	
          // status - On error occurred
          function(status:Object):void { 
            LogUtil.error("Error occurred:"); 
            for (var x:Object in status) { 
              LogUtil.error(x + " : " + status[x]); 
            } 
            sendConnectionFailedEvent(ConnectionFailedEvent.UNKNOWN_REASON);
          }
        )//new Responder
      ); //_netConnection.call
    }
    
    private function becomePresenterIfLoneModerator():void {
/*      LogUtil.debug("Checking if I need to become presenter.");
      var participants:Conference = UserManager.getInstance().getConference();
      if (participants.hasOnlyOneModerator()) {
        LogUtil.debug("There is only one moderator in the meeting. Is it me? ");
        var user:BBBUser = participants.getTheOnlyModerator();
        if (user.me) {
          LogUtil.debug("Setting me as presenter because I'm the only moderator. My userid is [" + user.userid + "]");
          var presenterEvent:RoleChangeEvent = new RoleChangeEvent(RoleChangeEvent.ASSIGN_PRESENTER);
          presenterEvent.userid = user.userid;
          presenterEvent.username = user.name;
          var dispatcher:Dispatcher = new Dispatcher();
          dispatcher.dispatchEvent(presenterEvent);
        } else {
          LogUtil.debug("No. It is not me. It is [" + user.userid + ", " + user.name + "]");
        }
      } else {
        LogUtil.debug("No. There are more than one moderator.");
      }
*/    }
    
    public function assignPresenter(userid:Number, name:String, assignedBy:Number):void {
      var nc:NetConnection = connService.connection;
      nc.call("participants.assignPresenter",// Remote function name
        new Responder(
          // On successful result
          function(result:Boolean):void { 
            
            if (result) {
              LogUtil.debug("Successfully assigned presenter to: " + userid);							
            }	
          },	
          // status - On error occurred
          function(status:Object):void { 
            LogUtil.error("Error occurred:"); 
            for (var x:Object in status) { 
              LogUtil.error(x + " : " + status[x]); 
            } 
          }
        ), //new Responder
        userid,
        name,
        assignedBy
      ); //_netConnection.call
    }
    
    /**
     * Called by the server to assign a presenter
     */
    public function assignPresenterCallback(userid:Number, name:String, assignedBy:Number):void {
/*      LogUtil.debug("assignPresenterCallback " + userid + "," + name + "," + assignedBy);
      var dispatcher:Dispatcher = new Dispatcher();
      var meeting:Conference = UserManager.getInstance().getConference();
      if (meeting.amIThisUser(userid)) {
        meeting.setMePresenter(true);				
        var e:MadePresenterEvent = new MadePresenterEvent(MadePresenterEvent.SWITCH_TO_PRESENTER_MODE);
        e.userid = userid;
        e.presenterName = name;
        e.assignerBy = assignedBy;
        
        dispatcher.dispatchEvent(e);													
      } else {				
        meeting.setMePresenter(false);
        var viewerEvent:MadePresenterEvent = new MadePresenterEvent(MadePresenterEvent.SWITCH_TO_VIEWER_MODE);
        viewerEvent.userid = userid;
        viewerEvent.presenterName = name;
        viewerEvent.assignerBy = assignedBy;
        
        dispatcher.dispatchEvent(viewerEvent);
      }
*/    }
    
    public function kickUser(userid:Number):void{
      _participantsSO.send("kickUserCallback", userid);
    }
    
    public function kickUserCallback(userid:Number):void{
      if (UserManager.getInstance().getConference().amIThisUser(userid)){
        dispatcher.dispatchEvent(new LogoutEvent(LogoutEvent.USER_LOGGED_OUT));
      }
    }
    
    public function participantLeft(user:Object):void { 			
/*      var participant:BBBUser = UserManager.getInstance().getConference().getParticipant(Number(user));
      
      var p:User = new User();
      p.userid = String(participant.userid);
      p.name = participant.name;
      
      UserManager.getInstance().participantLeft(p);
      UserManager.getInstance().getConference().removeParticipant(Number(user));	
      
      var dispatcher:Dispatcher = new Dispatcher();
      var joinEvent:ParticipantJoinEvent = new ParticipantJoinEvent(ParticipantJoinEvent.PARTICIPANT_JOINED_EVENT);
      joinEvent.participant = p;
      joinEvent.join = false;
      dispatcher.dispatchEvent(joinEvent);	
*/      
      
    }
    
    public function participantJoined(joinedUser:Object):void { 
      
      LogUtil.info("Joined as [" + joinedUser.userid + "," + joinedUser.name + "," + joinedUser.role + "]");
      
/*      var user:BBBUser = new BBBUser();
      user.userid = Number(joinedUser.userid);
      user.name = joinedUser.name;
      user.role = joinedUser.role;
      
      LogUtil.debug("User status: " + joinedUser.status.hasStream);
      
      LogUtil.info("Joined as [" + user.userid + "," + user.name + "," + user.role + "]");
      UserManager.getInstance().getConference().addUser(user);
      participantStatusChange(user.userid, "hasStream", joinedUser.status.hasStream);
      participantStatusChange(user.userid, "presenter", joinedUser.status.presenter);
      participantStatusChange(user.userid, "raiseHand", joinedUser.status.raiseHand);
      
      var participant:User = new User();
      participant.userid = String(user.userid);
      participant.name = user.name;
      participant.isPresenter = joinedUser.status.presenter;
      participant.role = user.role;
      UserManager.getInstance().participantJoined(participant);
      
      var dispatcher:Dispatcher = new Dispatcher();
      var joinEvent:ParticipantJoinEvent = new ParticipantJoinEvent(ParticipantJoinEvent.PARTICIPANT_JOINED_EVENT);
      joinEvent.participant = participant;
      joinEvent.join = true;
      dispatcher.dispatchEvent(joinEvent);	
 */     
    }
    
    /**
     * Called by the server to tell the client that the meeting has ended.
     */
    public function logout():void {
      var dispatcher:Dispatcher = new Dispatcher();
      var endMeetingEvent:BBBEvent = new BBBEvent(BBBEvent.END_MEETING_EVENT);
      dispatcher.dispatchEvent(endMeetingEvent);
    }
    
    
    /**
     * Callback from the server from many of the bellow nc.call methods
     */
    public function participantStatusChange(userid:Number, status:String, value:Object):void {
      LogUtil.debug("Received status change [" + userid + "," + status + "," + value + "]")			
      UserManager.getInstance().getConference().newUserStatus(userid, status, value);
      
      if (status == "presenter"){
        var e:PresenterStatusEvent = new PresenterStatusEvent(PresenterStatusEvent.PRESENTER_NAME_CHANGE);
        e.userid = userid;
        var dispatcher:Dispatcher = new Dispatcher();
        dispatcher.dispatchEvent(e);
      }		
    }
    
    public function raiseHand(userid:Number, raise:Boolean):void {
      var nc:NetConnection = connService.connection;			
      nc.call(
        "participants.setParticipantStatus",// Remote function name
        responder,
        userid,
        "raiseHand",
        raise
      ); //_netConnection.call
    }
    
    public function addStream(userid:Number, streamName:String):void {
      var nc:NetConnection = connService.connection;	
      nc.call(
        "participants.setParticipantStatus",// Remote function name
        responder,
        userid,
        "hasStream",
        "true,stream=" + streamName
      ); //_netConnection.call
    }
    
    public function removeStream(userid:Number, streamName:String):void {
      var nc:NetConnection = connService.connection;			
      nc.call(
        "participants.setParticipantStatus",// Remote function name
        responder,
        userid,
        "hasStream",
        "false,stream=" + streamName
      ); //_netConnection.call
    }
    
    private function netStatusHandler ( event : NetStatusEvent ):void {
      var statusCode : String = event.info.code;
      
      switch (statusCode)  {
        case "NetConnection.Connect.Success" :
          LogUtil.debug("UsersSOService:Connection Success");		
          sendConnectionSuccessEvent();			
          break;
        
        case "NetConnection.Connect.Failed" :			
          LogUtil.debug("UsersSOService:Connection to viewers application failed");
          sendConnectionFailedEvent(ConnectionFailedEvent.CONNECTION_FAILED);
          break;
        
        case "NetConnection.Connect.Closed" :									
          LogUtil.debug("UsersSOService:Connection to viewers application closed");
          sendConnectionFailedEvent(ConnectionFailedEvent.CONNECTION_CLOSED);
          break;
        
        case "NetConnection.Connect.InvalidApp" :				
          LogUtil.debug("UsersSOService::Viewers application not found on server");
          sendConnectionFailedEvent(ConnectionFailedEvent.INVALID_APP);
          break;
        
        case "NetConnection.Connect.AppShutDown" :
          LogUtil.debug("UsersSOService:Viewers application has been shutdown");
          sendConnectionFailedEvent(ConnectionFailedEvent.APP_SHUTDOWN);
          break;
        
        case "NetConnection.Connect.Rejected" :
          LogUtil.debug("UsersSOService:No permissions to connect to the viewers application" );
          sendConnectionFailedEvent(ConnectionFailedEvent.CONNECTION_REJECTED);
          break;
        
        default :
          LogUtil.debug("UsersSOService:default - " + event.info.code );
          sendConnectionFailedEvent(ConnectionFailedEvent.UNKNOWN_REASON);
          break;
      }
    }
    
    private function asyncErrorHandler ( event : AsyncErrorEvent ) : void
    {
      LogUtil.debug("UsersSOService:participantsSO asyncErrorHandler " + event.error);
      sendConnectionFailedEvent(ConnectionFailedEvent.ASYNC_ERROR);
    }
        
    private function sendConnectionFailedEvent(reason:String):void{
      /*var e:ConnectionFailedEvent = new ConnectionFailedEvent(ConnectionFailedEvent.CONNECTION_LOST);
      e.reason = reason;
      dispatcher.dispatchEvent(e);*/
    }
    
    private function sendConnectionSuccessEvent():void{
      //TODO
    }
    
    private var responder:Responder = new Responder(
      // On successful result
      function(result:Boolean):void { 	
      },	
      // On error occurred
      function(status:Object):void { 
        LogUtil.error("Error occurred:"); 
        for (var x:Object in status) { 
          LogUtil.error(x + " : " + status[x]); 
        } 
      }
    )
  }
}