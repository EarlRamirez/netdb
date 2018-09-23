/** NetDB Javascript Code **/

/** OnReady Event, show and hide different divs on page **/
$(document).ready(function(){

	// Submit Ready
	var submitReady = true;

	/** Initiate the Tooltip code **/
	tooltip();

	/** Notify IE6 Users that their browser sucks **/
	if ( $.browser.msie && $.browser.version=="6.0") {
	    $("#netdbnotice").append('<div class="messagebox info"> You may have to scroll down to see your results when using Internet Explorer 6.</div><br>');
	}

	/** JQuery Tabs **/
	$("#container-1").tabs({
		fx: { opacity: 'toggle', duration: 'fast' },
		    load: function(event, ui) {
  
		    $('.ajaxlink', ui.panel).livequery('click', function(event) {
			    $(ui.panel).load(this.href);
			    return false;
			});
		}
	    });                                                     

	/** Hide/Unhide different elements **/
	$(".messagebox").fadeIn(400); //Fade in warning div
	$(".notice").fadeIn(400); //Fade in notice message
	//$(".netdbresults").show( 'fold', '', 1000); //Fade in NetDB Results
	$(".netdbresults").fadeIn(300); //Fade in NetDB Results
	$(".loading").css('visibility', 'hidden'); //Hide all loading images

	initTableSorter();

	// Setup info dialog box
	$("#infodialog").dialog({
		bgiframe: true,
		    modal: true,
		    width: 450,
		    stack: false,
		    position: ['center', 230],
		    buttons: {
		    Ok: function() { $(this).dialog('close'); 
			$("#netdbaddress").focus(); }
		} //buttons
	    });
	// Setup error dialog box
	$("#errordialog").dialog({
		bgiframe: true,
		    modal: true,
		    width: 450,
		    stack: false,
		    position: ['center', 230],
		    buttons: {
		    Ok: function() { $(this).dialog('close'); 
			$("#netdbaddress").focus(); }
		} //buttons
	    }).prev().addClass('ui-state-highlight');


	// Allows enter key to close dialog only if dialog box is open
	$(document).bind("keydown.dialog-overlay", function(event) {
		if ( event.keyCode == 13 ) { 
		    if ( $("#infodialog").length > 0 && $("#infodialog").dialog("isOpen") ) { 
			$("#infodialog").dialog("close");
			return false; // Stops event propogation
		    }
		    else if ( $("#errordialog").length > 0 && $("#errordialog").dialog("isOpen") ) {
			$("#errordialog").dialog("close");
			return false;
		    }
		    else {
			return true;
		    }
		}
	    });


	/*************************/
	/** Disable Client Dialog **/
	/*************************/

	$("#disabledialog").dialog({
		autoOpen: false,
		    bgiframe: true,
		    modal: true,
		    width: 600,
		    height: 550,
		    stack: false,
		    position: ['center', 150]
		    });

	// Clicked on Disable Client Box
	$(".disclient").click(function() {
		$(".loading").css('visibility', 'hidden'); //Hide all loading images

		// Get the mac
		var myLoc = $(this).attr('href'); 

		// Strip the anchor out of the address location to get just the switchport
		myLoc = myLoc.replace(/#disable-/i, "");

		// Change the switchport value to reflect the selected switchport
		$("#disablemac").val(myLoc);

		// Add text for dialog box
		$("#disabletext").html("<b>Do you want to Shutdown or Block Internet Access for " + myLoc + "?</b>" );


		$("#disableform").show();

		//alert("Thanks for visiting!");

		$("#disabledialog").dialog("open");


	    });
	//Disable AJAX Submit
	$("#disableform").submit(function() {

		// Build ajax submit string
		var myLoc = document.location.toString();

		// Get the switch and port passed
		myLoc = myLoc.split("#disable-")[1];
   

		var myType = "unknown";
		//       var myType  = $("#blocktype").val();
		$(".loading").css('visibility', 'visible');

		if ( $("#blockfirewall:checked").is(":checked") ) {
		    myType = "nonetnac";
		}
		if ($("#blockshut:checked").is(":checked") ) {
		    myType = "shutdown";
		}

		var dataString = "skiptemplate=1&stage=1&disableclient=1&disablemac=" + myLoc + "&blocktype=" + myType;
		//alert(dataString);

		$("#disableform").hide();     
		$("#disabletext").html("<br><br><br>Attempting to Disable Device (Press esc to close)<br>");

		$.ajax({
			type: "POST",
			    url: "$scriptLocation",
			    data: dataString,
			    success: function( data ) {

			    // Print results 
			    $("#disabletext").html(data);
			    $(".loading").css('visibility', 'hidden'); //Hide all loading images
			    //Move focus to dialog box
			    $("#caseid").focus();  
			    $("#caseid").select();

			}
		    });

		//$(".loading").css('visibility', 'hidden'); //Hide all loading images

		return false;
	    });


	/******************/
	/** Enable Box     **/
	/******************/

	/******************/
	/** Enable Box     **/
	/******************/

	$("#enabledialog").dialog({
		autoOpen: false,
		    bgiframe: true,
		    modal: true,
		    width: 610,
		    height: 275,
		    stack: false,
		    position: ['center', 150]
		    });
                                                                                                                                             


	// Clicked on Enable Client Box
	$(".enableclient").click(function() {
		$(".loading").css('visibility', 'hidden'); //Hide all loading images

		// Get the mac
		var myLoc = $(this).attr('href'); 

		// Strip the anchor out of the address location to get just the switchport
		myLoc = myLoc.replace(/#enable-/i, "");

		var results = myLoc.split("-");

		myLoc = results[0];
		var type = results[1];

		// Change the switchport value to reflect the selected switchport
		$("#enablemac").val(myLoc);

		// Add text for dialog box
		$("#enabletext").text("Are you sure you want to remove security block (" + type + ") for " + myLoc + " ?" );


		$("#enableform").show();

		//alert("Thanks for visiting!");

		$("#enabledialog").dialog("open");


	    });

	$("#enableform").submit(function() {

		// Build ajax submit string
		var myLoc = document.location.toString();

		// Get the switch and port passed
		myLoc = myLoc.split("#enable-")[1];
   
		var results = myLoc.split("-");                                                                                                                                           
                               
		myLoc = results[0];
		var type = results[1];
		var severe = results[2];
		var myNote = $("#enablenote").val();

     $(".loading").css('visibility', 'visible');

     var dataString = "skiptemplate=1&stage=3&disableclient=1&disablemac=" + myLoc + "&blocktype=" + type + "&note=" + myNote + "&severe=" + severe;
     // alert(dataString);

     $("#enableform").hide();     
     $("#enabletext").html("<br><br><br>Attempting to Enable Client (Press esc to close)<br>");
     // Ajax onclick to call camtrace with skiptemplate, then print results to ajaxresults div
     $.ajax({
    type: "POST",
    url: "$scriptLocation",
    data: dataString,
    success: function( data ) {

                  // Print results 
                  $("#enabletext").html(data);
                  $(".loading").css('visibility', 'hidden'); //Hide all loading images
                    //Move focus to dialog box
      }
     });

   //$(".loading").css('visibility', 'hidden'); //Hide all loading images

   return false;
 });



/**********************/
/** Vlan Change Dialog **/
/**********************/

$("#vlandialog").dialog({
       autoOpen: false,
       bgiframe: true,
       modal: true,
       width: 450,
       height: 240,
       stack: false,
       position: ['center', 230]
});
 


// Clicked on dialog box link, spawn dialog
$(".vlanchange").click(function() {
  $(".loading").css('visibility', 'hidden'); //Hide all loading images

  $("#vlanform").show();

  // Get the port clicked on
  var myLoc = $(this).attr('href');

  // Strip the anchor out of the address location to get just the switchport
  myLoc = myLoc.replace(/#vlanchange-/i, "");

  // Change the switchport value to reflect the selected switchport
  $("#vlanswitchport").val(myLoc);

  // Add text for dialog box
  $("#vlantext").text("What VLAN do you want to change port " + myLoc + " to?" );
  $("#vlandialog").dialog("open");

  //Move focus to dialog box
  $("#vlanid").focus();
  $("#vlanid").select();

  //return false;
  });

// IE Fix to catch click for ajax submit (if it fails, does a normal post action)
 $("#vlansubmit").click(function() {
    $("#vlanform").submit();
    return false;
 });

 // IE Fix for pressing enter to submit form in vlanid box
 $("#vlanid").bind("keydown", function (e) {
    var key = e.keyCode || e.which;
    if (key === 13 && $.browser.msie ) { $("#vlanform").submit(); }
 });


//VLAN Change AJAX Submit
 $("#vlanform").submit(function() {

     // Build ajax submit string
     var myLoc = document.location.toString();

     // Get the switch and port passed
     myLoc = myLoc.split("#vlanchange-")[1];
   
     // Get the VLAN value
     var myVlan = $("#vlanid").val();    
     var myVoice = $("#voicevlan").val();
     $(".loading").css('visibility', 'visible');

     var dataString = "skiptemplate=1&vlanchange=1&vlan=" + myVlan + "&voicevlan=" + myVoice + "&vlanswitchport=" + myLoc;
     //alert(dataString);

     $("#vlanform").hide();     
     $("#vlantext").html("<br><br><br>Changing port, wait for verification or move on to other ports. (Press esc to close)<br>");
     $("#loadingvlan").show();
		// Ajax onclick to call camtrace with skiptemplate, then print results to ajaxresults div
		$.ajax({
			type: "POST",
			    url: "$scriptLocation",
			    data: dataString,
			    success: function( data ) {

			    // Print results after camtrace.pl returns
			    $("#vlantext").html(data);
			    $(".loading").css('visibility', 'hidden'); //Hide all loading images
			}
		    });

		//$(".loading").css('visibility', 'hidden'); //Hide all loading images

		return false;
	    });


	// Select and focus on Address by default on load
	$("#netdbaddress").focus();
	$("#netdbaddress").select();


    }); //END $(document).ready(function(){});


/** FUNCTIONS **/


function initTableSorter() {
    /** Table Sorter Code
     *
     * Parser to sort by port
     **/
    $.tablesorter.addParser({ 
	    // set a unique id 
	    id: 'port', 
		is: function(s) { 
		// return false so this parser is not auto detected 
		return false; 
	    }, 
		format: function(s) { 
		// format your data for normalization
		s = s.toLowerCase().replace(/gi/i, "10").replace(/fa/i, "10").replace(/eth/i, "10"); //strip out the Gi and Fa
		s = s.toLowerCase().replace(/te/i, "10").replace(/po/i, "100000").replace(/v10/i, "200000");
		var splitResult = s.split("/"); // Split on the / character
		var num1 = parseFloat(splitResult[0]); // Convert string to numbers
            
		var num2 = 1;
		if( splitResult[2] ) {
		    num2  = parseFloat(splitResult[1]);
		}

		var num3 = 1;
		if( splitResult[2] ) {
		    num3  = parseFloat(splitResult[2]);
		}
		var myReturn = num1*100000+num2*1000+num3;   // Add a weights to port sections
		return myReturn;
	    }, 
		// set type, either numeric or text 
		type: 'numeric' 
		}); 

    // Sort by IP Address
    $.tablesorter.addParser({
	    // set a unique id
	    id: 'customIP',
		is: function(s) {
		// return false so this parser is not auto detected
		return false;
	    },
		format: function(s) {
		// format your data for normalization
		var splitIP = s.split("."); // Split on the . character
		var num1 = parseFloat(splitIP[0]); // Convert string to numbers
		var num2 = parseFloat(splitIP[1]);
		var num3 = parseFloat(splitIP[2]);
		var num4 = parseFloat(splitIP[3]);
		var myReturn = num1*1000000000+num2*100000+num3*1000+num4;   // Add a weights to port sections

		return myReturn;
	    },
		// set type, either numeric or text
		type: 'numeric'
		});

    // ARP Table
    $("#netdbipmac").tablesorter({
	    sortList: [[0,0]],
		headers: {
		0: { sorter: "customIP" }
	    } 
	});

    // MAC Table
    $("#netdbmac").tablesorter({
	    headers: {
		1: { sorter: "customIP" },
		    4: { sorter: "text" },
		    5: { sorter: "port" }
	    }
	});

    // Switchport Table
    $("#netdbswitch").tablesorter({
	    sortList: [[0,0], [1,0]],
		headers: {
		1: { sorter: "port" },
		    6: { sorter: "ipAddress" }
	    }
	});
}

/** Tooltip Code **/
this.tooltip = function(){
    /** CONFIG **/
    xOffset = 10;
    yOffset = 20;
    // these 2 variable determine popup's distance from the cursor
    // you might want to adjust to get the right result
    /** END CONFIG **/
    $("a.tooltip").hover(function(e){
	    this.t = this.title;
	    this.title = "";
	    $("body").append("<p id='tooltip'>"+ this.t +"</p>");
	    $("#tooltip")
		.css("top",(e.pageY - xOffset) + "px")
		.css("left",(e.pageX + yOffset) + "px")
		.fadeIn("fast");
	},
	function(){
	    this.title = this.t;
	    $("#tooltip").remove();
	});
    $("a.tooltip").mousemove(function(e){
	    $("#tooltip")
		.css("top",(e.pageY - xOffset) + "px")
		.css("left",(e.pageX + yOffset) + "px");
	});

};

