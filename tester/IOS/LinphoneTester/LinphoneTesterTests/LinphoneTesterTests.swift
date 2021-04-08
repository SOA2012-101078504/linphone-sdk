
//
//  LinphoneTesterTests.swift
//  LinphoneTester
//
//  Created by QuentinArguillere on 25/02/2021.
//  Copyright © 2021 belledonne. All rights reserved.
//

import Foundation
import XCTest
import linphonesw
import AVFoundation

func getCacheDirectory() -> URL {
	let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
	return paths[0]
}

class LinphoneTestUser {
	var setupDNSDelegate : CoreDelegate!
	var core : Core!
	var manager : UnsafeMutablePointer<LinphoneCoreManager>!
	let rcFile : String
	init(rcFile : String) {
		self.rcFile = rcFile
		XCTContext.runActivity(named: "Setup \(rcFile)") { _ in
			manager = linphone_core_manager_new(rcFile)
			core = Core.getSwiftObject(cObject: manager.pointee.lc)
			core.autoIterateEnabled = true
			
			setupDNSDelegate = CoreDelegateStub(onGlobalStateChanged: { (lc: Core, gstate: GlobalState, message: String) in
				if (gstate == .Configuring) {
					liblinphone_tester_set_dns_engine_by_default(lc.getCobject)
					linphone_core_set_dns_servers(lc.getCobject, flexisip_tester_dns_ip_addresses)
				} else if (gstate == .Startup) {
					let transport = try! Factory.Instance.createTransports()
					transport.tcpPort = -1
					transport.tlsPort = -1
					try! lc.setTransports(newValue: transport)
				}
			})
			core.addDelegate(delegate: setupDNSDelegate)
		}
	}
	
	deinit {
		core = nil
		setupDNSDelegate = nil
		linphone_core_manager_destroy(manager)
	}
	
	func stopCore(stoppedCoreExpectation: XCTestExpectation, waitFn : @escaping()->Void) {
		XCTContext.runActivity(named: "Stop \(rcFile) core") { _ in
			let coreStoppedDelegate = CoreDelegateStub(onGlobalStateChanged: { (lc: Core, gstate: GlobalState, message: String) in
				if (gstate == GlobalState.Off){
					stoppedCoreExpectation.fulfill()
				}
			})
			core.addDelegate(delegate: coreStoppedDelegate)
			core.stopAsync()
			waitFn()
			core.removeDelegate(delegate: coreStoppedDelegate)
		}
	}
	
	func startCore(startedCoreExpectation: XCTestExpectation, waitFn : @escaping()->Void) {
		XCTContext.runActivity(named: "Start \(rcFile) core") { _ in
			let coreStartedDelegate = CoreDelegateStub(onGlobalStateChanged: { (lc: Core, gstate: GlobalState, message: String) in
				if (gstate == GlobalState.On){
					startedCoreExpectation.fulfill()
				}
			})
			core.addDelegate(delegate: coreStartedDelegate)
			try! core.start()
			waitFn()
			core.removeDelegate(delegate: coreStartedDelegate)
		}
	}
	
	func waitForRegistration(registeredExpectation: XCTestExpectation, requireVoipToken : Bool = true, isInverted: Bool = false, waitFn : @escaping()->Void) {
		var activityName : String
		if (isInverted) {
			activityName = "Waiting to make sure that \(rcFile) does not register"
		} else {
			activityName = "Registering \(rcFile) " + (requireVoipToken ? "(with voip token)" : "")
		}
		XCTContext.runActivity(named: activityName) { _ in
			registeredExpectation.assertForOverFulfill = false
			let registeredDelegate = AccountDelegateStub(onRegistrationStateChanged: { (account: Account, state: RegistrationState, message: String) in
				if (state == .Ok) {
					if (!requireVoipToken || !account.params!.pushNotificationConfig!.voipToken.isEmpty) {
						registeredExpectation.fulfill()
					}
				}
			})
			core.defaultAccount!.addDelegate(delegate: registeredDelegate)
			waitFn()
		}
	}
	
	func waitForVoipPushIncoming(voipPushIncomingExpectation: XCTestExpectation, callAndWaitFn : @escaping() -> Void) {
		XCTContext.runActivity(named: "Receiving voip push on \(rcFile)") { _ in
			let receivedPushDelegate = CoreDelegateStub(onCallStateChanged: { (lc: Core, call: Call, cstate: Call.State, message: String) in
				if (cstate == .PushIncomingReceived){
					voipPushIncomingExpectation.fulfill()
				}
			})
			core.addDelegate(delegate: receivedPushDelegate)
			callAndWaitFn()
			core.removeDelegate(delegate: receivedPushDelegate)
		}
	}
}

class PhysicalDeviceIncomingPushTests: XCTestCase {
	
	override class func setUp() {
		super.setUp()
		liblinphone_tester_set_disable_CU_environment(1)
	}
	
	var currentTestName : String!
	override func setUp() {
		super.setUp()
		
		// get the name and remove the class name and what comes before the class name
		currentTestName = self.name.replacingOccurrences(of: "-[PhysicalDeviceIncomingPushTests ", with: "")
		// And then you'll need to remove the closing square bracket at the end of the test name
		currentTestName = currentTestName.replacingOccurrences(of: "]", with: "_logs.txt")
		
		let logFile = bc_tester_file(currentTestName.cString(using: String.Encoding.utf8))
		liblinphone_tester_set_log_file(logFile)
	}
	
	
	override func tearDown() {
		let attachment = XCTAttachment(contentsOfFile: getCacheDirectory().appendingPathComponent(currentTestName))
		attachment.lifetime = .keepAlways
		add(attachment)
		
		liblinphone_tester_set_log_file("")
		super.tearDown()
	}
	/*
	 func testTokenReception() {
	 NotificationCenter.default.addObserver(self,
	 selector:#selector(self.receivedPushCallback),
	 name: NSNotification.Name(rawValue: kPushReceivedEvent),
	 object:nil);
	 
	 
	 tokenReceivedExpect = expectation(description: "Token received by push")
	 var creatorCallbackExpect = expectation(description: "OnSendToken callback")
	 creatorCallbacks.expect = creatorCallbackExpect
	 
	 creator.pnPrid =  (UIApplication.shared.delegate as! AppDelegate).pushToken! as String
	 creator.pnParam = "testteam.\(Bundle.main.bundleIdentifier! as String)"
	 creator.pnProvider = "apns.dev"
	 
	 creator.addDelegate(delegate: creatorCallbacks)
	 
	 
	 //_ = creator.sendTokenFlexiapi()
	 
	 waitForExpectations(timeout: 20)
	 
	 }
	 
	 */
	
	
	func cleanupTestUser(tester : LinphoneTestUser) {
		XCTContext.runActivity(named: "Cleaning up \(tester.rcFile)") { _ in
			let core = tester.core!
			core.autoIterateEnabled = true
			if (core.globalState == .Off) {
				let registeredExpec = expectation(description: "Registering for cleanup")
				let coreDelegate = CoreDelegateStub(onAccountRegistrationStateChanged: { (core: Core, account: Account, state: RegistrationState, message: String) in
					if (state == .Ok) {
						registeredExpec.fulfill()
					}
				})
				core.addDelegate(delegate: coreDelegate)
				try! core.start()
				waitForExpectations(timeout: 5)
				core.removeDelegate(delegate: coreDelegate)
			}
			
			if let acc = core.defaultAccount {
				if (acc.state != .Ok) {
					let registeredExpec = expectation(description: "Registering for cleanup")
					let registeredDelegate = AccountDelegateStub(onRegistrationStateChanged: { (account: Account, state: RegistrationState, message: String) in
						if (state == .Ok) {
							registeredExpec.fulfill()
						}
					})
					acc.addDelegate(delegate: registeredDelegate)
					waitForExpectations(timeout: 5)
					acc.removeDelegate(delegate: registeredDelegate)
				}
				
				let params = acc.params
				let clonedParams = params?.clone()
				clonedParams?.registerEnabled = false
				acc.params = clonedParams
				let clearedExpec = expectation(description: "Cleared register")
				let clearedDelegate = AccountDelegateStub(onRegistrationStateChanged: { (account: Account, state: RegistrationState, message: String) in
					if (state == .Cleared) {
						clearedExpec.fulfill()
					}
				})
				core.defaultAccount!.addDelegate(delegate: clearedDelegate)
				waitForExpectations(timeout: 5)
				core.defaultAccount!.removeDelegate(delegate: clearedDelegate)
			}
		}
	}
	
	func testCallToSRTPMandatoryEncryptionWithNoEncryptionEnabled() {
		let marie = LinphoneTestUser(rcFile: "marie_rc")
		try! marie.core.setMediaencryption(newValue: .None)
		marie.core.avpfMode = .Enabled
		
		let pauline = LinphoneTestUser(rcFile: "pauline_push_enabled_rc")
		try! pauline.core.setMediaencryption(newValue: .SRTP)
		pauline.core.mediaEncryptionMandatory = true
		
		pauline.waitForRegistration(registeredExpectation: expectation(description: "Pauline voip registered")) {
			self.waitForExpectations(timeout: 5)
		}
		let paulineAddress = pauline.core.defaultAccount!.params!.identityAddress!.asString()
		
		pauline.stopCore(stoppedCoreExpectation: self.expectation(description: "Pauline Core Stopped")) {
			self.waitForExpectations(timeout: 5)
		}
		
		var call1, call2 : Call?
		
		XCTContext.runActivity(named: "Pauline receives 2 voip push for a single call") { _ in
			let expectPush1Incoming = expectation(description: "PushIncoming 1 received")
			let expectPush2Incoming = expectation(description: "PushIncoming 2 received")
			// We expect 2 calls because once the first call fails, a second one will start to check if it was due to AVPF and not SRTP
			let receivedPushDelegate = CoreDelegateStub(onCallStateChanged: { (lc: Core, call: Call, cstate: Call.State, message: String) in
				if (cstate == .PushIncomingReceived){
					if (call1 == nil) {
						expectPush1Incoming.fulfill()
						call1 = call
					} else if (call2 == nil) {
						expectPush2Incoming.fulfill()
						call2 = call
					}
				}
			})
			pauline.core.addDelegate(delegate: receivedPushDelegate)
			_ = marie.core.invite(url: paulineAddress)
			self.waitForExpectations(timeout: 10)
		}
		
		cleanupTestUser(tester: marie)
		cleanupTestUser(tester: pauline)
		
	}
	
	func testNoVoipTokenInRegistrationWhenPushAreDisabled() {
		let marie = LinphoneTestUser(rcFile: "marie_rc")
		let ensureNotRegisteredAgainExp = expectation(description: "Check that Marie does not register with voip token")
		ensureNotRegisteredAgainExp.isInverted = true // Inverted expectation, this test ensures that Marie does not register with a voip token
		
		marie.waitForRegistration(registeredExpectation: ensureNotRegisteredAgainExp, isInverted: true) {
			self.waitForExpectations(timeout: 5)
		}
		cleanupTestUser(tester: marie)
	}
	
	func testUpdateRegisterWhenPushConfigurationChanges() {
		let pauline = LinphoneTestUser(rcFile: "pauline_push_enabled_rc")
		
		pauline.waitForRegistration(registeredExpectation: expectation(description: "testUpdateRegisterWhenPushConfigurationChanges -- Registered with voip token")) {
			self.waitForExpectations(timeout: 5)
		}
		
		let paulineAccount = pauline.core.defaultAccount!
		var newPaulineParams = paulineAccount.params?.clone()
		paulineAccount.params = newPaulineParams
		
		newPaulineParams = paulineAccount.params?.clone()
		newPaulineParams?.pushNotificationConfig?.provider = "testprovider"
		paulineAccount.params = newPaulineParams
		pauline.waitForRegistration(registeredExpectation: expectation(description: "testUpdateRegisterWhenPushConfigurationChanges -- register again when changing provider")) {
			self.waitForExpectations(timeout: 5)
		}
		
		newPaulineParams = paulineAccount.params?.clone()
		newPaulineParams?.pushNotificationConfig?.param = "testparams"
		paulineAccount.params = newPaulineParams
		pauline.waitForRegistration(registeredExpectation: expectation(description: "testUpdateRegisterWhenPushConfigurationChanges -- register again when changing params")) {
			self.waitForExpectations(timeout: 5)
		}
		
		newPaulineParams = paulineAccount.params?.clone()
		newPaulineParams?.pushNotificationConfig?.prid = "testprid"
		paulineAccount.params = newPaulineParams
		pauline.waitForRegistration(registeredExpectation: expectation(description: "testUpdateRegisterWhenPushConfigurationChanges -- register again when changing prid")) {
			self.waitForExpectations(timeout: 5)
		}
		
		cleanupTestUser(tester: pauline)
	}
	
	func voipPushStopWhenDisablingPush(willDisableCorePush: Bool) { // if false, will disable account push allowed instead
		let marie = LinphoneTestUser(rcFile: "marie_rc")
		
		// ONLY A SINGLE VOIP PUSH REGISTRY EXIST PER APP.
		// IF YOU INSTANCIATE SEVERAL CORES, MAKE SURE THAT THE ONE THAT WILL PROCESS PUSH NOTIFICATION IS CREATE LAST
		let pauline = LinphoneTestUser(rcFile: "pauline_push_enabled_rc")
		
		pauline.waitForRegistration(registeredExpectation: expectation(description: "TestVoipPushCall - Registered with voip token")) {
			self.waitForExpectations(timeout: 5)
		}
		
		var paulineAddress = pauline.core.defaultAccount!.params!.identityAddress!.asString()
		pauline.stopCore(stoppedCoreExpectation: self.expectation(description: "Pauline Core Stopped")) { self.waitForExpectations(timeout: 10)	}
		
		var call : Call?
		XCTContext.runActivity(named: "Marie calls Pauline, Pauline receives the voip push before the sip invite since core is stopped") { _ in
			let expectPushIncomingState = expectation(description: "Incoming Push Received")
			var receivedPushFirst = false
			let expectIncomingReceivedState = expectation(description: "Sip invite received")
			let basicPaulineIncomingCallDelegate = CoreDelegateStub(onCallStateChanged: { (lc: Core, call: Call, cstate: Call.State, message: String) in
				if (cstate == .IncomingReceived){
					XCTAssertTrue(receivedPushFirst)
					expectIncomingReceivedState.fulfill()
				} else if (cstate == .PushIncomingReceived) {
					receivedPushFirst = true
					expectPushIncomingState.fulfill()
				}
			})
			pauline.core.addDelegate(delegate: basicPaulineIncomingCallDelegate)
			
			call = marie.core.invite(url: paulineAddress)
			self.waitForExpectations(timeout: 5)
			
			pauline.core.removeDelegate(delegate: basicPaulineIncomingCallDelegate)
			
			let expectCallTerminated = self.expectation(description: "Call terminated expectation - iteration")
			let callTerminatedDelegate = CallDelegateStub(onStateChanged: { (thisCall: Call, state: Call.State, message : String) in
				if (state == Call.State.Released) {
					expectCallTerminated.fulfill()
				}
			})
			call?.addDelegate(delegate: callTerminatedDelegate)
			try! call!.terminate()
			self.waitForExpectations(timeout: 5)
		}
		
		// Now, check that we do not receive it anymore when we disable push
		XCTContext.runActivity(named: "Disabling push notifications for Pauline") { _ in
			if (willDisableCorePush) {
				pauline.core.pushNotificationEnabled = false
			} else {
				let newParams = pauline.core.defaultAccount!.params!.clone()!
				newParams.pushNotificationAllowed = false
				pauline.core.defaultAccount!.params = newParams
			}
			pauline.waitForRegistration(registeredExpectation: expectation(description: "TestVoipPushCall - Registered after disabling core push"), requireVoipToken: false) {
				self.waitForExpectations(timeout: 5)
			}
		}
		paulineAddress = pauline.core.defaultAccount!.params!.identityAddress!.asString()
		pauline.stopCore(stoppedCoreExpectation: self.expectation(description: "Pauline Core Stopped")) { self.waitForExpectations(timeout: 10)	}
		
		XCTContext.runActivity(named: "Marie calls Pauline, but Pauline does not receive it because push are disabled") { _ in
			let expectNoCall = expectation(description: "Do not receive call when push is disabled")
			expectNoCall.isInverted = true
			let ensureNoIncomingCallDelegate = CoreDelegateStub(onCallStateChanged: { (lc: Core, call: Call, cstate: Call.State, message: String) in
				expectNoCall.fulfill()
			})
			pauline.core.addDelegate(delegate: ensureNoIncomingCallDelegate)
			
			call = marie.core.invite(url: paulineAddress)
			self.waitForExpectations(timeout: 5)
			pauline.core.removeDelegate(delegate: ensureNoIncomingCallDelegate)
		}
		cleanupTestUser(tester: marie)
		cleanupTestUser(tester: pauline)
	}
	func testVoipPushStopWhenDisablingCorePush() {
		voipPushStopWhenDisablingPush(willDisableCorePush: true)
	}
	func testVoipPushStopWhenDisablingAccountPush() {
		voipPushStopWhenDisablingPush(willDisableCorePush: false)
	}
	
	func testOverrideOldAccountPnPrid() {
		let marie = LinphoneTestUser(rcFile: "marie_rc")
		
		// ONLY A SINGLE VOIP PUSH REGISTRY EXIST PER APP.
		// IF YOU INSTANCIATE SEVERAL CORES, MAKE SURE THAT THE ONE THAT WILL PROCESS PUSH NOTIFICATION IS CREATE LAST
		let pauline = LinphoneTestUser(rcFile: "pauline_push_enabled_rc")
		
		pauline.waitForRegistration(registeredExpectation: expectation(description: "TestVoipPushCall - Registered with voip token")) {
			self.waitForExpectations(timeout: 5)
		}
		
		let voipToken = pauline.core.defaultAccount?.params?.pushNotificationConfig?.voipToken
		let prid = pauline.core.defaultAccount?.params?.pushNotificationConfig?.prid
		
		pauline.stopCore(stoppedCoreExpectation: expectation(description: "Pauline Core Stopped")) {
			self.waitForExpectations(timeout: 5)
		}
		
		let testPushParams = "pn-prid=NOTAREALTOKEN:voip;pn-provider=apns.dev;pn-param=ABCD1234.belledonne.LinphoneTester.voip"
		pauline.core.config?.setString(section: "proxy_0", key: "push_parameters", value: testPushParams)
		
		pauline.startCore(startedCoreExpectation: expectation(description: "Pauline Core Started")) {
			XCTAssertEqual(pauline.core.defaultAccount?.params?.pushNotificationConfig?.prid, "NOTAREALTOKEN:voip")
			self.waitForExpectations(timeout: 5)
		}
		pauline.waitForRegistration(registeredExpectation: expectation(description: "TestVoipPushCall - Registered with modified voip token")) {
			self.waitForExpectations(timeout: 5)
		}
		
		XCTContext.runActivity(named: "Token and prid from the config should be overwritten") { _ in
			let newVoipToken = pauline.core.defaultAccount?.params?.pushNotificationConfig?.voipToken
			let newPrid = pauline.core.defaultAccount?.params?.pushNotificationConfig?.prid
			XCTAssertEqual(voipToken, newVoipToken)
			XCTAssertEqual(prid, newPrid)
		}
		cleanupTestUser(tester: marie)
		cleanupTestUser(tester: pauline)
	}
	
	var tokenReceivedExpect : XCTestExpectation!
	var pushReceivedExpect : XCTestExpectation!
	func receivedPushTokenCallback() {
		tokenReceivedExpect.fulfill()
	}
	func receivedPushNotificationCallback() {
		pushReceivedExpect.fulfill()
	}
	
	func testVoipPushCallWithManualManagement() {
		XCTContext.runActivity(named: "Manually requesting and receiving VOIP token") { _ in
			tokenReceivedExpect = expectation(description: "VOIP Push Token received")
			NotificationCenter.default.addObserver(self,
												   selector:#selector(self.receivedPushTokenCallback),
												   name: NSNotification.Name(rawValue: kPushTokenReceived),
												   object:nil);
			
			(UIApplication.shared.delegate as! AppDelegate).enableVoipPush()
			waitForExpectations(timeout: 5)
		}
		let voipToken = (UIApplication.shared.delegate as! AppDelegate).voipToken!
		
		let marie = LinphoneTestUser(rcFile: "marie_rc")
		let pauline = LinphoneTestUser(rcFile: "pauline_rc")
		
		let paulineAccount = pauline.core.defaultAccount!
		let newParams = paulineAccount.params!.clone()
		newParams?.pushNotificationAllowed = true
		newParams?.pushNotificationConfig?.voipToken = voipToken
		newParams!.contactUriParameters = "pn-prid=" + voipToken + ";pn-provider=apns.dev;pn-param=ABCD1234.belledonne.LinphoneTester.voip;pn-silent=1;pn-timeout=0"
		paulineAccount.params = newParams
		
		pauline.waitForRegistration(registeredExpectation: expectation(description: "TestVoipPushCall - Registered with voip token")) {
			self.waitForExpectations(timeout: 5)
		}
		
		NotificationCenter.default.addObserver(self,
											   selector:#selector(self.receivedPushNotificationCallback),
											   name: NSNotification.Name(rawValue: kPushNotificationReceived),
											   object:nil);
		
		let paulineAddress = pauline.core.defaultAccount!.params!.identityAddress!.asString()
		pauline.stopCore(stoppedCoreExpectation: self.expectation(description: "Pauline Core Stopped")) { self.waitForExpectations(timeout: 10)	}
		
		XCTContext.runActivity(named: "Marie calls Pauline, a VOIP push is received") { _ in
			pushReceivedExpect = expectation(description: "VOIP Push notification received")
			var call = marie.core.invite(url: paulineAddress)
			self.waitForExpectations(timeout: 10)
		}
		cleanupTestUser(tester: marie)
		cleanupTestUser(tester: pauline)
	}
	
	func testAnswerCallBeforePushIsReceivedOnSecondDevice() {
		let marie = LinphoneTestUser(rcFile: "marie_rc")
		let basicPauline = LinphoneTestUser(rcFile: "pauline_rc")
		
		// ONLY A SINGLE VOIP PUSH REGISTRY EXIST PER APP. IF YOU INSTANCIATE SEVERAL CORES, MAKE SURE THAT THE ONE THAT WILL PROCESS PUSH NOTIFICATION IS CREATE LAST
		let pushPauline = LinphoneTestUser(rcFile: "pauline_push_enabled_rc")
		let pushTimeoutInSecond = 5
		pushPauline.core.pushIncomingCallTimeout = pushTimeoutInSecond
		pushPauline.core.defaultAccount?.params?.conferenceFactoryUri = "sip:conference@fakeserver.com"
		pushPauline.waitForRegistration(registeredExpectation: expectation(description: "testAnswerCallBeforePushIsReceivedOnSecondDevice - Registered with voip token")) {
			self.waitForExpectations(timeout: 5)
		}
		
		pushPauline.stopCore(stoppedCoreExpectation: expectation(description: "Pauline Core Stopped")) {
			self.waitForExpectations(timeout: 5)
		}
		
		var marieCall : Call?
		XCTContext.runActivity(named: "Marie calls Pauline. Pauline1 accepts before Pauline2 receives the voip push. Pauline2's call times out.") { _ in
			let expectSipInviteAccepted = self.expectation(description: "Sip invite received")
			let basicPaulineIncomingCallDelegate = CoreDelegateStub(onCallStateChanged: { (lc: Core, call: Call, cstate: Call.State, message: String) in
				if (cstate == .IncomingReceived){
					try! call.accept()
				} else if (cstate == .PushIncomingReceived) {
					XCTAssertFalse(false, "Should never receive push on this user")
				} else if (cstate == .StreamsRunning) {
					expectSipInviteAccepted.fulfill()
				}
			})
			basicPauline.core.addDelegate(delegate: basicPaulineIncomingCallDelegate)
			
			let expectPushIncoming = self.expectation(description: "Incoming Push Received")
			let expectPushCallTimedOutTooSoon = self.expectation(description: "Push Call timed out too soon")
			expectPushCallTimedOutTooSoon.isInverted = true
			let pushPaulineIncomingCallDelegate = CoreDelegateStub(onCallStateChanged: { (lc: Core, call: Call, cstate: Call.State, message: String) in
				if (cstate == .PushIncomingReceived){
					expectPushIncoming.fulfill()
				} else if (cstate == .End) {
					expectPushCallTimedOutTooSoon.fulfill()
				}
			})
			pushPauline.core.addDelegate(delegate: pushPaulineIncomingCallDelegate)
			
			marieCall = marie.core.invite(url: basicPauline.core.defaultAccount!.params!.identityAddress!.asString())
			self.waitForExpectations(timeout: TimeInterval(pushTimeoutInSecond - 1))
			basicPauline.core.removeDelegate(delegate: basicPaulineIncomingCallDelegate)
			pushPauline.core.removeDelegate(delegate: pushPaulineIncomingCallDelegate)
			
			let expectPushCallTimedOut = self.expectation(description: "Push Call timed out when expected")
			let pushPaulineTimedOutDelegate = CoreDelegateStub(onCallStateChanged: { (lc: Core, call: Call, cstate: Call.State, message: String) in
				if (cstate == .End) {
					expectPushCallTimedOut.fulfill()
				}
			})
			pushPauline.core.addDelegate(delegate: pushPaulineTimedOutDelegate)
			self.waitForExpectations(timeout: 5)
			pushPauline.core.removeDelegate(delegate: pushPaulineTimedOutDelegate)
		}
		
		XCTContext.runActivity(named: "Marie terminates the call") { _ in
			let expectCallTerminated = self.expectation(description: "Call terminated expectation")
			let callTerminatedDelegate = CallDelegateStub(onStateChanged: { (thisCall: Call, state: Call.State, message : String) in
				if (state == Call.State.Released) {
					expectCallTerminated.fulfill()
				}
			})
			marieCall?.addDelegate(delegate: callTerminatedDelegate)
			
			try! marieCall!.terminate()
			self.waitForExpectations(timeout: 5)
		}
		cleanupTestUser(tester: marie)
		cleanupTestUser(tester: basicPauline)
		cleanupTestUser(tester: pushPauline)
	}
	
	func testDeclineCallBeforeReceivingSipInvite() {
		let marie = LinphoneTestUser(rcFile: "marie_rc")
		
		// ONLY A SINGLE VOIP PUSH REGISTRY EXIST PER APP. IF YOU INSTANCIATE SEVERAL CORES, MAKE SURE THAT THE ONE THAT WILL PROCESS PUSH NOTIFICATION IS CREATE LAST
		let pauline = LinphoneTestUser(rcFile: "pauline_push_enabled_rc")
		pauline.waitForRegistration(registeredExpectation: expectation(description: "Registered with voip token")) {
			self.waitForExpectations(timeout: 5)
		}
		let paulineAddress = pauline.core.defaultAccount!.params!.identityAddress!.asString()
		
		pauline.stopCore(stoppedCoreExpectation: expectation(description: "Pauline Core Stopped")) {
			self.waitForExpectations(timeout: 5)
		}
		
		XCTContext.runActivity(named: "Marie calls Pauline. Pauline declines when she receives the voip push, and never receives the SIP invite") { _ in
			pauline.core.autoIterateEnabled = false // Disable auto iterate to ensure that we do not receive SIP invite before pauline declines the call
			let ensureSipInviteDelegate = CoreDelegateStub(onCallStateChanged: { (lc: Core, call: Call, cstate: Call.State, message: String) in
				if (cstate == .IncomingReceived) {
					XCTAssertFalse(true, "Should never receive sip invite before pauline declines the call")
				}
			})
			pauline.core.addDelegate(delegate: ensureSipInviteDelegate)
			
			pauline.waitForVoipPushIncoming(voipPushIncomingExpectation: expectation(description: "Incoming Push Received")) {
				marie.core.invite(url: paulineAddress)
				self.waitForExpectations(timeout: 5)
			}
			
			let paulineCall = pauline.core.currentCall
			
			let expectCallTerminated = self.expectation(description: "Call terminated expectation")
			let callTerminatedDelegate = CallDelegateStub(onStateChanged: { (thisCall: Call, state: Call.State, message : String) in
				if (state == Call.State.Released) {
					expectCallTerminated.fulfill()
				}
			})
			paulineCall?.addDelegate(delegate: callTerminatedDelegate)
			
			try! paulineCall!.decline(reason: Reason.Declined)
			pauline.core.removeDelegate(delegate: ensureSipInviteDelegate)
			pauline.core.autoIterateEnabled = true
			self.waitForExpectations(timeout: 5)
		}
		cleanupTestUser(tester: marie)
		cleanupTestUser(tester: pauline)
	}
	
	func testAcceptCallBeforeReceivingSipInvite() {
		let marie = LinphoneTestUser(rcFile: "marie_rc")
		marie.core.pushNotificationEnabled = false
		
		// ONLY A SINGLE VOIP PUSH REGISTRY EXIST PER APP. IF YOU INSTANCIATE SEVERAL CORES, MAKE SURE THAT THE ONE THAT WILL PROCESS PUSH NOTIFICATION IS CREATE LAST
		let pauline = LinphoneTestUser(rcFile: "pauline_push_enabled_rc")
		pauline.waitForRegistration(registeredExpectation: expectation(description: "Registered with voip token")) {
			self.waitForExpectations(timeout: 5)
		}
		let paulineAddress = pauline.core.defaultAccount!.params!.identityAddress!.asString()
		
		pauline.stopCore(stoppedCoreExpectation: expectation(description: "Pauline Core Stopped")) {
			self.waitForExpectations(timeout: 5)
		}
		
		var ensureSipInviteDelegate : CoreDelegateStub!
		XCTContext.runActivity(named: "Marie calls Pauline. Pauline receives the voip push but not the SIP invite, since auto iterate is disabled") { _ in
			pauline.core.autoIterateEnabled = false // Disable auto iterate to ensure that we do not receive SIP invite before pauline declines the call
			ensureSipInviteDelegate = CoreDelegateStub(onCallStateChanged: { (lc: Core, call: Call, cstate: Call.State, message: String) in
				if (cstate == .IncomingReceived) {
					XCTAssertFalse(true, "Should never receive sip invite before pauline accepts the call")
				}
			})
			pauline.core.addDelegate(delegate: ensureSipInviteDelegate)
			
			pauline.waitForVoipPushIncoming(voipPushIncomingExpectation: expectation(description: "Incoming Push Received")) {
				_ = marie.core.invite(url: paulineAddress)
				self.waitForExpectations(timeout: 5)
			}
		}
		
		var paulineCall: Call?
		XCTContext.runActivity(named: "Pauline accepts the call before receiving the sip invite") { _ in
			paulineCall = pauline.core.currentCall
			
			let expectCallRunning = self.expectation(description: "Call running expectation")
			let callRunningDelegate = CallDelegateStub(onStateChanged: { (thisCall: Call, state: Call.State, message : String) in
				if (state == Call.State.StreamsRunning) {
					expectCallRunning.fulfill()
				}
			})
			paulineCall?.addDelegate(delegate: callRunningDelegate)
			
			try! paulineCall!.accept()
			pauline.core.removeDelegate(delegate: ensureSipInviteDelegate)
			
			pauline.core.autoIterateEnabled = true
			self.waitForExpectations(timeout: 5)
			paulineCall?.removeDelegate(delegate: callRunningDelegate)
		}
		
		
		XCTContext.runActivity(named: "Pauline terminates the call") { _ in
			let expectCallTerminated = self.expectation(description: "Call terminated expectation")
			let callTerminatedDelegate = CallDelegateStub(onStateChanged: { (thisCall: Call, state: Call.State, message : String) in
				if (state == Call.State.Released) {
					expectCallTerminated.fulfill()
				}
			})
			paulineCall?.addDelegate(delegate: callTerminatedDelegate)
			
			try! paulineCall!.terminate()
			self.waitForExpectations(timeout: 5)
		}
		cleanupTestUser(tester: marie)
		cleanupTestUser(tester: pauline)
	}
	
	func testChatroom() {
		XCTContext.runActivity(named: "Requesting and waiting for remote push token") { _ in
			tokenReceivedExpect = expectation(description: "Push Token received")
			tokenReceivedExpect.assertForOverFulfill = false
			NotificationCenter.default.addObserver(self,
												   selector:#selector(self.receivedPushTokenCallback),
												   name: NSNotification.Name(rawValue: kRemotePushTokenReceived),
												   object:nil);
			
			UIApplication.shared.registerForRemoteNotifications()
			waitForExpectations(timeout: 10)
		}
		
		let marie = LinphoneTestUser(rcFile: "marie_rc")
		let marieCore = marie.core!
		
		let pauline = LinphoneTestUser(rcFile: "pauline_push_enabled_rc")
		let paulineCore = pauline.core!
		
		let paulineAccount = paulineCore.defaultAccount!
		let enablePushParams = paulineAccount.params!.clone()
		enablePushParams?.pushNotificationAllowed = false
		enablePushParams?.remotePushNotificationAllowed = true
		paulineAccount.params = enablePushParams
		
		paulineCore.didRegisterForRemotePush(deviceToken: Factory.Instance.userData)
		
		XCTContext.runActivity(named: "Pauline registers with remote push token") { _ in
			let remoteTokenAdded = expectation(description: "pauline registered with remote push token")
			let paulineRegisterDelegate = AccountDelegateStub(onRegistrationStateChanged: { (account: Account, state: RegistrationState, message: String) in
				let token = account.params!.pushNotificationConfig!.remoteToken
				if (!token.isEmpty) {
					remoteTokenAdded.fulfill()
				}
			})
			paulineAccount.addDelegate(delegate: paulineRegisterDelegate)
			waitForExpectations(timeout: 10)
			paulineAccount.removeDelegate(delegate: paulineRegisterDelegate)
		}
		
		
		pauline.stopCore(stoppedCoreExpectation: expectation(description: "Pauline Core Stopped")) {
			self.waitForExpectations(timeout: 5)
		}
		
		XCTContext.runActivity(named: "Marie sends a chat message to Pauline. Pauline receives a remote push notification") { _ in
			pushReceivedExpect = expectation(description: "Push Notification received")
			pushReceivedExpect.assertForOverFulfill = false
			NotificationCenter.default.addObserver(self,
												   selector:#selector(self.receivedPushNotificationCallback),
												   name: NSNotification.Name(rawValue: kPushNotificationReceived),
												   object:nil);
			let chatParams = try! marieCore.createDefaultChatRoomParams()
			chatParams.backend = ChatRoomBackend.Basic
			let marieChatroom = try! marieCore.createChatRoom(params: chatParams, localAddr: marieCore.defaultAccount!.contactAddress, participants: [paulineAccount.contactAddress!])
			let chatMsg = try! marieChatroom.createMessageFromUtf8(message: "TestMessage")
			chatMsg.send()
			
			waitForExpectations(timeout: 10)
		}
		
		cleanupTestUser(tester: marie)
		cleanupTestUser(tester: pauline)
	}
	
	func testUnregisteringOnStop() {
		let pauline = LinphoneTestUser(rcFile: "pauline_push_enabled_rc")
		pauline.waitForRegistration(registeredExpectation: expectation(description: "Registered with voip token")) {
			self.waitForExpectations(timeout: 5)
		}
		
		func stopAndStart(clearedExpect: XCTestExpectation, shouldClear: Bool) {
			XCTContext.runActivity(named: "Stop and restart Pauline core " + (shouldClear ? "(unregistering on stop)" : "(timeout to check that we stay registered on stop)")) { _ in
				let coreDelegate = CoreDelegateStub(onAccountRegistrationStateChanged:  { (core: Core, account: Account, state: RegistrationState, message: String) in
					if (state == .Cleared) {
						clearedExpect.fulfill()
					}
				})
				pauline.core.addDelegate(delegate: coreDelegate)
				pauline.stopCore(stoppedCoreExpectation: expectation(description: "Pauline Core Stopped")) {
					self.waitForExpectations(timeout: 5)
				}
				pauline.core.removeDelegate(delegate: coreDelegate)
				pauline.startCore(startedCoreExpectation: expectation(description: "Pauline Core Started")) {
					self.waitForExpectations(timeout: 5)
				}
				pauline.waitForRegistration(registeredExpectation: expectation(description: "Registered"), requireVoipToken: false) {
					self.waitForExpectations(timeout: 5)
				}
			}
		}
		
		let expectNoClear = expectation(description: "Push Enabled, should not be cleared")
		expectNoClear.isInverted = true
		stopAndStart(clearedExpect: expectNoClear, shouldClear: false)
		
		var paulineAccount: Account!
		var newPaulineParams: AccountParams!
		XCTContext.runActivity(named: "Disable voip push, enable remote push") { _ in
			paulineAccount = pauline.core.defaultAccount!
			newPaulineParams = paulineAccount.params?.clone()
			newPaulineParams?.pushNotificationAllowed = false
			newPaulineParams?.remotePushNotificationAllowed = true
			paulineAccount.params = newPaulineParams
			
			pauline.waitForRegistration(registeredExpectation: expectation(description: "Registered"), requireVoipToken: false) {
				self.waitForExpectations(timeout: 5)
			}
		}
		
		let expectNoClear2 = expectation(description: "Remote Push Enabled, should not be cleared")
		expectNoClear2.isInverted = true
		stopAndStart(clearedExpect: expectNoClear2, shouldClear: false)
		
		XCTContext.runActivity(named: "Disable both voip and remote push") { _ in
			paulineAccount = pauline.core.defaultAccount!
			newPaulineParams = paulineAccount.params?.clone()
			newPaulineParams?.pushNotificationAllowed = false
			newPaulineParams?.remotePushNotificationAllowed = false
			paulineAccount.params = newPaulineParams
			pauline.waitForRegistration(registeredExpectation: expectation(description: "Registered"), requireVoipToken: false) {
				self.waitForExpectations(timeout: 5)
			}
		}
		
		let expectClear = expectation(description: "Cleared")
		stopAndStart(clearedExpect: expectClear, shouldClear: true)
		
		cleanupTestUser(tester: pauline)
	}
}


class PhysicalDeviceAudioRoutesTests: XCTestCase {
	
	override class func setUp() {
		super.setUp()
		liblinphone_tester_set_disable_CU_environment(1)
	}
	
	override func setUp() {
		// get the name and remove the class name and what comes before the class name
		var currentTestName = self.name.replacingOccurrences(of: "-[PhysicalDeviceAudioRoutesTests ", with: "")
		// And then you'll need to remove the closing square bracket at the end of the test name
		currentTestName = currentTestName.replacingOccurrences(of: "]", with: "_logs.txt")
		
	}
	
	func testDefaultRoute() {
		let logFile = bc_tester_file("test")
		liblinphone_tester_set_log_file(logFile)
		
		let marie = LinphoneTestUser(rcFile: "marie_rc")
		let pauline = LinphoneTestUser(rcFile: "pauline_rc")
		marie.core.useFiles = true
		pauline.core.useFiles = false
		
		var marieCall : Call?
		XCTContext.runActivity(named: "Pauline accepts a call from Marie. Sound is on Microphone/Receiver") { _ in
			let expectSipInviteAccepted = self.expectation(description: "Sip invite received")
			let paulineIncomingCallDelegate = CoreDelegateStub(onCallStateChanged: { (lc: Core, call: Call, cstate: Call.State, message: String) in
				if (cstate == .IncomingReceived){
					try! call.accept()
				} else if (cstate == .StreamsRunning) {
					expectSipInviteAccepted.fulfill()
				}
			})
			pauline.core.addDelegate(delegate: paulineIncomingCallDelegate)
			
			marieCall = marie.core.invite(url: pauline.core.defaultAccount!.params!.identityAddress!.asString())
			self.waitForExpectations(timeout: 5)
			XCTAssertEqual(AVAudioSession.sharedInstance().currentRoute.outputs[0].portType, AVAudioSession.Port.builtInReceiver)
		}
		
	}
	
	func testSetDefaultOutputDeviceToSpeaker() {
		let marie = LinphoneTestUser(rcFile: "marie_rc")
		let pauline = LinphoneTestUser(rcFile: "pauline_rc")
		
		marie.core.useFiles = true
		pauline.core.useFiles = false
		XCTContext.runActivity(named: "Set Pauline default output device to Speaker") { _ in
			pauline.core.defaultOutputAudioDevice = pauline.core.audioDevices.first { $0.type == AudioDeviceType.Speaker }
		}
		
		var marieCall : Call?
		XCTContext.runActivity(named: "Pauline accepts a call from Marie. Sound is on Speaker by default") { _ in
			let expectSipInviteAccepted = self.expectation(description: "Sip invite received")
			let paulineIncomingCallDelegate = CoreDelegateStub(onCallStateChanged: { (lc: Core, call: Call, cstate: Call.State, message: String) in
				if (cstate == .IncomingReceived){
					try! call.accept()
				} else if (cstate == .StreamsRunning) {
					expectSipInviteAccepted.fulfill()
				}
			})
			pauline.core.addDelegate(delegate: paulineIncomingCallDelegate)
			
			marieCall = marie.core.invite(url: pauline.core.defaultAccount!.params!.identityAddress!.asString())
			self.waitForExpectations(timeout: 5)
			XCTAssertEqual(AVAudioSession.sharedInstance().currentRoute.outputs[0].portType, AVAudioSession.Port.builtInSpeaker)
		}
		
	}
	
	var routeChangeExpec : XCTestExpectation?
	@objc func audioRouteChangedEvent(notification: Notification) {
		routeChangeExpec?.fulfill()
	}
	
	func testSetOutputDeviceDuringCall() {
		let marie = LinphoneTestUser(rcFile: "marie_rc")
		let pauline = LinphoneTestUser(rcFile: "pauline_rc")
		
		marie.core.useFiles = true
		pauline.core.useFiles = false
		
		var marieCall : Call?
		XCTContext.runActivity(named: "Pauline accepts a call from Marie. Sound is on Microphone/Receiver") { _ in
			let expectSipInviteAccepted = self.expectation(description: "Sip invite received")
			let paulineIncomingCallDelegate = CoreDelegateStub(onCallStateChanged: { (lc: Core, call: Call, cstate: Call.State, message: String) in
				if (cstate == .IncomingReceived){
					try! call.accept()
				} else if (cstate == .StreamsRunning) {
					expectSipInviteAccepted.fulfill()
				}
			})
			pauline.core.addDelegate(delegate: paulineIncomingCallDelegate)
			
			marieCall = marie.core.invite(url: pauline.core.defaultAccount!.params!.identityAddress!.asString())
			self.waitForExpectations(timeout: 5)
			XCTAssertEqual(AVAudioSession.sharedInstance().currentRoute.outputs[0].portType, AVAudioSession.Port.builtInReceiver)
		}
		
		
		XCTContext.runActivity(named: "While call is running, change output device to Speaker") { _ in
			let nc = NotificationCenter.default
			nc.addObserver(self,
						   selector: #selector(audioRouteChangedEvent),
						   name: AVAudioSession.routeChangeNotification,
						   object: nil)
			
			routeChangeExpec = self.expectation(description: "Audio route changed")
			routeChangeExpec?.assertForOverFulfill = false
			pauline.core.outputAudioDevice = pauline.core.audioDevices.first { $0.type == AudioDeviceType.Speaker }
			waitForExpectations(timeout: 5)
			XCTAssertEqual(AVAudioSession.sharedInstance().currentRoute.outputs[0].portType, AVAudioSession.Port.builtInSpeaker)
		}
	}
}