/*
 Copyright 2014 Esri
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "LicenseHelper.h"
#import "LicenseHelperConstants.h"

#define kUntrustedHostAlertViewTag 0
#define kErrorAlertViewTag         1
#define kCredentialKey @"credential"
#define kLicenseKey @"license"

@interface LicenseHelper () <AGSPortalDelegate>

@property (nonatomic, strong) AGSOAuthLoginViewController* oauthLoginVC;
@property (nonatomic, strong) AGSViewController* parentVC;
@property (nonatomic, strong) NSURL* portalURL;
@property (nonatomic, strong) NSError* error;
@property (nonatomic, strong, readwrite) AGSPortal* portal;
@property (nonatomic, strong) void(^completionBlock)(AGSLicenseResult licenseResult, BOOL usedSavedLicenseInfo, NSError *error);
@property (nonatomic, strong, readwrite) AGSCredential* credential;
@property (nonatomic, strong) AGSKeychainItemWrapper* keychainWrapper;

@end

@implementation LicenseHelper

static LicenseHelper* _sharedLicenseHelper = nil;

+(LicenseHelper*)sharedLicenseHelper {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedLicenseHelper = [[super alloc] init];
        _sharedLicenseHelper.keychainWrapper = [[AGSKeychainItemWrapper alloc]
                                                initWithIdentifier:kKeyChainKey accessGroup:nil];
    });
    
    return _sharedLicenseHelper;
}

+(id)alloc {
    @synchronized([LicenseHelper class]) {
        NSAssert(YES, @"Cannot alloc LicenseHelper, use 'sharedLicenseHelper' to access the LicenseHelper.");
    }
    return nil;
}

-(void)standardLicenseFromPortal:(NSURL *)portalURL
            parentViewController:(AGSViewController *)parentVC
                      completion:(void (^)(AGSLicenseResult licenseResult,
                                           BOOL usedSavedLicenseInfo,
                                           NSError *error))completion
{
    
    self.completionBlock = completion;
    self.parentVC = parentVC;
    self.portalURL = portalURL;
    
    if ([self autoLicense]) {
        //saved license information was found and we've set a valid license, now
        //login using saved credentials.  The completion block will by called by
        //either portalDidLoad: or portal:didFailToLoadWithError:
        self.portal = [[AGSPortal alloc]initWithURL:self.portalURL credential:self.credential];
        self.portal.delegate = self;
    }
    else {
        //need login and online
        [self login];
    }
}

-(void)unlicense {
    //reset the portal
    self.portal = nil;
    self.credential = nil;
    
    //remove stored license info, which will force a login next time the app starts
    [self.keychainWrapper reset];
}

-(BOOL)savedInformationExists {
    return ([self.keychainWrapper keychainObject] != nil);
}

-(AGSLicenseLevel)licenseLevel {
    return [[AGSRuntimeEnvironment license] licenseLevel];
}

-(NSDate *)expiryDate {
    return [[AGSRuntimeEnvironment license] expiry];
}

#pragma mark - AGSPortalDelegate

-(void)portalDidLoad:(AGSPortal *)portal {
    
    //check to see if we already have saved license information from the keychain.
    //If we do, this means we've used that saved information to license the app
    //and log in to the portal; therefore, can just call the completion block and return
    if ([self savedInformationExists]) {
        //we have been called after retrieving the license from the keychain.
        //The fact that this completed means we're on-line
        [self callCompletionHandler:AGSLicenseResultValid usedSavedLicenseInfo:YES error:nil];
        return;
    }

    //portal loaded Ok, get license info
    NSError *error = nil;
    AGSLicenseResult result;
    AGSLicenseInfo *licenseInfo = [[AGSLicenseInfo alloc] initWithPortalInfo:portal.portalInfo];
    if ([[AGSRuntimeEnvironment license] licenseLevel] == AGSLicenseLevelStandard) {
        //already licensed, don't re-license because that's not allowed
        //but we will store the licenseInfo for the current portal, below
        result = AGSLicenseResultValid;
    }
    else {
        result = [[AGSRuntimeEnvironment license] setLicenseInfo:licenseInfo];
    }
    
    if (result == AGSLicenseResultExpired) {
        error = [self errorWithDescription:@"License has expired"];
    }
    else if (result == AGSLicenseResultInvalid) {
        error = [self errorWithDescription:@"License is invalid"];
    }
    else if (result == AGSLicenseResultValid) {
        //store license info json and credential in a new dictionary
        //we know we don't already have stored keychain data because of the first check above
        NSDictionary *keyChainDict = @{ kLicenseKey : [licenseInfo encodeToJSON],
                                    kCredentialKey : self.credential,
                                    };

        //store the new dictionary in the keychain
        [self.keychainWrapper setKeychainObject:keyChainDict];
    }
    
    //we're done, call the completion handler
    [self callCompletionHandler:result usedSavedLicenseInfo:NO error:error];
}

-(void)portal:(AGSPortal *)portal didFailToLoadWithError:(NSError *)error {
    
    //if the license level is already standard, then we tried to load the portal using stored credentials
    BOOL usingSavedLicenseInfo = ([[AGSRuntimeEnvironment license] licenseLevel] == AGSLicenseLevelStandard);

    AGSLicenseResult result = AGSLicenseResultInvalid;

    if (usingSavedLicenseInfo && error.code == kCFURLErrorNotConnectedToInternet) {
        //no internet error; we are using saved info and offline; ignore the error
        //The fact that we got this far with saved info means the license is valid
        result = AGSLicenseResultValid;
        error = nil;
    }
    self.portal = nil;
    [self callCompletionHandler:result usedSavedLicenseInfo:usingSavedLicenseInfo error:error];
}

#pragma mark - internal

-(void)cancelLogin {
    [self.parentVC dismissViewControllerAnimated:YES completion:nil];
    [self callCompletionHandler:AGSLicenseResultLoginRequired usedSavedLicenseInfo:NO error:[self userCancelledError]];
}

-(BOOL)autoLicense {
    
    BOOL success = NO;
    
    //Determine if we already are logged in; i.e., if we have an license info json key in the keychain
    NSDictionary *keyChainDict = (NSDictionary *)[self.keychainWrapper keychainObject];
    NSDictionary *licenseInfoJSON = keyChainDict[kLicenseKey];
    if (licenseInfoJSON) {
        //Having a stored dictionary means we've already logged in sometime in the past...
        //Create license info and set it into the license, then check the result
        AGSLicenseInfo *licenseInfo = [[AGSLicenseInfo alloc] initWithJSON:licenseInfoJSON];
        AGSLicenseResult result = [[AGSRuntimeEnvironment license] setLicenseInfo:licenseInfo];
        if (result == AGSLicenseResultValid) {
            //license result is valid, no prompting for user credentials required
            //get self.credential from keychainDict
            self.credential = (AGSCredential *)keyChainDict[kCredentialKey];
            success = YES;
        }
        else {
            //There's a problem with the saved credentials.  Delete them.
            [self.keychainWrapper reset];
        }
    }
    
    return success;
}

-(void)login {
    self.oauthLoginVC = [[AGSOAuthLoginViewController alloc] initWithPortalURL:self.portalURL clientID:kClientID];
    self.oauthLoginVC.cancelButtonHidden = NO;
    
    UINavigationController* nvc = [[UINavigationController alloc]initWithRootViewController:self.oauthLoginVC];
    nvc.modalTransitionStyle = UIModalTransitionStyleFlipHorizontal;
    self.oauthLoginVC.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]initWithTitle:@"Cancel" style:UIBarButtonItemStyleBordered target:self action:@selector(cancelLogin)];
    [self.parentVC presentViewController:nvc animated:YES completion:nil];
    
    __weak LicenseHelper *safeSelf = self;
    self.oauthLoginVC.completion = ^(AGSCredential *credential, NSError *error) {
        if (error) {
            if (error.code == NSUserCancelledError) {
                [safeSelf cancelLogin];
            } else if (error.code == NSURLErrorServerCertificateUntrusted){
                //keep a reference to the error so that the uialertview deleate can accesss it
                safeSelf.error = error;

                UIAlertView *av = [[UIAlertView alloc]initWithTitle:@"Error" message:[[error localizedDescription] stringByAppendingString:[error localizedRecoverySuggestion]] delegate:safeSelf cancelButtonTitle:@"Cancel" otherButtonTitles:@"Yes", nil];
                av.tag = kUntrustedHostAlertViewTag;
                [av show];
            }
            else {
                UIAlertView *av = [[UIAlertView alloc]initWithTitle:@"Error" message:[error localizedDescription] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
                av.tag = kErrorAlertViewTag;
                [av show];
            }
        } else {
            //update the portal explorer with the credential provided by the user.
            AGSPortal* portal = [[AGSPortal alloc]initWithURL:safeSelf.portalURL credential:credential];
            portal.delegate = safeSelf;
            safeSelf.portal = portal;
            safeSelf.credential = credential;
            
            [safeSelf.parentVC dismissViewControllerAnimated:YES completion:nil];
            //The execution will continue in the AGSPortalDelegate methods
        }
    };
}

-(NSError *)errorWithDescription:(NSString *)description {
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    [userInfo setValue:description forKey:NSLocalizedDescriptionKey];
    
    return [NSError errorWithDomain:@"com.esri.arcgis.licensehelper.error"
                               code:0
                           userInfo:[NSDictionary dictionaryWithDictionary:userInfo]];
}

-(NSError *)userCancelledError {
    return [self errorWithDescription:@"User cancelled portal login"];
}

-(void)callCompletionHandler:(AGSLicenseResult)licenseResult usedSavedLicenseInfo:(BOOL)usedSavedLicenseInfo error:(NSError *)error {
    if (self.completionBlock) {
        self.completionBlock(licenseResult, usedSavedLicenseInfo, error);
        self.completionBlock = nil;
    }
}

#pragma mark - UIAlertViewDelegate

- (void) alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    
    if (alertView.tag == kErrorAlertViewTag) {
        //error, retry until user cancels
        [self.oauthLoginVC reload];
    }
    else if (alertView.tag == kUntrustedHostAlertViewTag) {
        //host is untrusted
        if (buttonIndex == 0) {
            //user doesn't want to trust host
            [self cancelLogin];
        } else {
            NSURL* url = [self.error userInfo][NSURLErrorFailingURLErrorKey];
            //add to trusted hosts
            [[NSURLConnection ags_trustedHosts]addObject:[url host]];
            //make a test connection to force UIWebView to accept the host
            AGSJSONRequestOperation* rop = [[AGSJSONRequestOperation alloc]initWithURL:url];
            [[AGSRequestOperation sharedOperationQueue] addOperation:rop];
            [self.oauthLoginVC reload];
        }
    }
}


@end
