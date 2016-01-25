Registration Engine
=====================

In LTI 2.0+ the first page of configuring a Tool Consumer (TC) with a Tool Provider (TP) is to perform a Registration.  The Registration process takes metadata that advertises the capabilities offered by the Tool Consumer and matches it with the capabilities offered by the Tool Provider.  It then creates a lowest-common denominator contract called the ToolProxy that represents the specific interface contract between TC and TP.  Finally it generates the shared secret for the TC and TP and creates a portion of the ToolProxy called the SecurityContract.  The ToolProxy is then used by both TC and TP to configure themselves.  This process is described extensively in various LTI 2 documents--particularly the LTI 2 Implementation Guide.  (cf. http://imsglobal.org/lti).

Typically the registration process on the Tool Provider is built into the LTI 2 implementation and served by the same server as the LTI launches and services themselves.  This RegistrationEngine (RE) project takes a different approach.  It creates a standalone registration process, that is fully compliant to LTI 2.1, but breaks off the registration from the Tool Provider process.  This registration process can be served on a different endpoint, even a different server, than the run-time Tool Provider code.

Motivation for a separate registration engine
---------------------------------------------

Registration is a complicated part of the implementation.  Furthermore, it gets more complicated with re-registration that is supported in LTI 2.1.  This project relieves the LTI 2 TP developer from dealing with registration.  Note that this registration process is written in Ruby/Rails but can generate a ToolProxy for any LTI 2 implementaiton.  This is because the ToolProxy itself is expressed in JSON-LD which is language-neutral.

API between Registration Engine and the Tool Provider
-----------------------------------------------------

A standalone registration engine needs some user-created extension points that perform a few parts of the registration that can't be genericized.  There is a web-service interface layer between registration engine and tool provider that supports provided the application-specific customizations.  Since this interface layer is a web-service these extenion points can be written in any language as well.

The extension points are paths on to a configured 'lti_tool_provider_url' base url (see Configuration below):


/get_tool_provider_review
	This services implements a user experience (user interface and/or workflow) for the necessary customization of the registration process.  In other words, this service supplies an TP-specific prerequisite processing for a registration
	
	query parameters:
		* registration_id -- an RE provided unique identifier for the registration
		* returns_url -- endpoint to return to after the tool provider review
		* status -- 
		* tcp_uri
		* consumer_key -- the consumer key provided by the ToolConsumer

/get tool_profile
	This services requests the Tool Profile that is relevant to the partner as determined by the tool provider review
	
	query parameters
		* registration_id
		
/get change_credentials
	This service allows the RE to provide the final, generated secret to the TP.
	
	query parameters
		* registration_id
		* final_secret