//
//  pathmarker.lsl -- move marker to given location, resize, and color.
//
//  The marker has a straight center section and two end caps.
//
//  Gets parameters over a channel via JSON.
//
//  This normally goes in temporary objects.
//
//  Animats
//  July, 2019
//
//
//  Constants
//
integer MARKERCHANNEL = -3938235;                                   // arbitrary channel number
integer MARKERREPLYCHANNEL = -3938236;                              // reply channel                         
//
//  Globals
integer gListenHandle = 0;                                          // our listen handle
integer gId = 0;
//
//  setposlong -- llSetPos for long moves
//
setposlong(vector pos)
{   integer n = 37;             //  sqrt(256^2 + 256^2)/10                                    
    do {
        llSetPos(pos);
        vector newpos = llGetPos();
        if (llVecMag(pos - newpos) < 0.05) return;
        
    } while(--n > 0);
    llSay(DEBUG_CHANNEL, "Unable to set position to " + (string)pos + ". Stuck at " + (string) llGetPos());   // unlikely
}

//
//  setmarker -- set marker parameters
//
//  This marker has three prims. The root prim is a cube and at the center.
//  The end prims are half-cylinders.
//
setmarker(vector pos, rotation rot, vector scale, vector color, float alpha)
{
    llSetScale(scale);
    llSetRot(rot);
    setposlong(pos);                            // this takes time
    llSetColor(color,ALL_SIDES);                // 
    llSetAlpha(alpha,ALL_SIDES);
    vector offset = <scale.x*0.5,0,0>;          // place end caps
    llSetLinkPrimitiveParamsFast(2,[PRIM_SIZE,<scale.y, scale.y,scale.z>, PRIM_COLOR,ALL_SIDES,color, alpha, PRIM_POS_LOCAL, offset]);
    llSetLinkPrimitiveParamsFast(3,[PRIM_SIZE,<scale.y, scale.y,scale.z>, PRIM_COLOR,ALL_SIDES,color, alpha, PRIM_POS_LOCAL, -offset]);
}

//
//  handlemsg -- handle incoming JSON message
//
//  Format:
//  {"request": "marker", "id": INTEGER, "pos" : VECTOR, "rot" : ROTATION, "scale" : VECTOR,
//      "color": VECTOR, "alpha": FLOAT}
//
handlemsg(integer channel, string name, key id, string message)
{
    ////llOwnerSay("Marker msg: " + message);               // ***TEMP***
    if (channel != MARKERCHANNEL) { return; }   // not ours
    if ((integer)llJsonGetValue(message, ["id"] ) != gId) { return; } // not our message
    string request = llJsonGetValue(message, ["request"]);       // what to do
    if (request != "marker")                            // not valid 
    {   llSay(DEBUG_CHANNEL, "Invalid request to marker: " + message); return; }
    vector pos = (vector)llJsonGetValue(message,["pos"]);   // get params
    rotation rot = (rotation)llJsonGetValue(message,["rot"]);
    vector scale = (vector)llJsonGetValue(message,["scale"]); 
    vector color = (vector)llJsonGetValue(message,["color"]); 
    float alpha = (float)llJsonGetValue(message,["alpha"]); 
    llListenRemove(gListenHandle);                          // one message for us and we are done
    gListenHandle = 0;                                      // not listening
    setmarker(pos, rot, scale, color, alpha);               // apply params
    //  Could turn off script at this point.
}

default
{

    on_rez(integer param)
    {   if (param == 0) { return; }                         // if rezzed not by program
        gId = param;
        gListenHandle = llListen(MARKERCHANNEL, "", NULL_KEY, ""); 
        ////llOwnerSay(llList2Json(JSON_OBJECT,["reply","marker","id",gId]));  // we're rezzed, tell us what to do    // ***TEMP***    
        llSay(MARKERREPLYCHANNEL, llList2Json(JSON_OBJECT,["reply","marker","id",gId]));  // we're rezzed, tell us what to do
    }
        
    listen(integer channel, string name, key id, string message)
    {
        handlemsg(channel, name, id, message);              // told what to do
    }
}

