/*
Author        	| Date             		| Description
Abdullah       | 3/12/2020  	  | Release 1.1
*/

public without sharing class XiqSync {
    
    
    // Will sync SF accounts to XIQ companies
    public static Integer syncInitialCompanies(Map<String,List<Account>> userAccounts, xiQ_User_Tokens__c xiqToken) {
        
        // final Map of User and associated List of Accounts
        Map<String,List<XiqCompany>> mapOfAccounts;
        xiQIncSF1__xiQ_User_Tokens__c setupUser = [Select Id,xiQIncSF1__User_ID__c,xiQIncSF1__Token__c,xiQIncSF1__Notify_Email__c from xiQIncSF1__xiQ_User_Tokens__c where User_ID__c =: UserInfo.getUserId()][0];
        Integer companiesProcessed = 0;
        
        try {
            
            // Getting map of Users and accounts from param userAccounts
            Map<String,List<Account>> accountsMap = userAccounts;
            mapOfAccounts = new Map<String,List<XiqCompany>>();
            
            // Looping through the keys in the map
            // constructing a list of XiqCompany object for every account associated to user
            // List is passed to backend in the body of Endpoint call
            for (String s : accountsMap.keyset()) {
                
                // Querying by Email to obtain Token of the associated User 
                xiQ_User_Tokens__c relatedUser = [Select Id,xiQIncSF1__User_ID__c,xiQIncSF1__Token__c,xiQIncSF1__Notify_Email__c from xiQIncSF1__xiQ_User_Tokens__c where Notify_Email__c =: s][0];
                List<Account> accountsList = accountsMap.get(s);
                List<XiqCompany> objWrapperList = new List<XiqCompany>();
                
                if (accountsList.size() > 0) {
                    for (Account a : accountsList) {
                        
                        XiqCompany objXiqComp= new XiqCompany();  
                        objXiqComp.salesforce_id = a.id;
                        objXiqComp.companyName = a.Name;
                        objXiqComp.website = a.Website;
                        
                        if(relatedUser != null) {
                            objXiqComp.username = relatedUser.Notify_Email__c;
                            objXiqComp.token = relatedUser.Token__c;
                        }
                        
                        if(Test.isRunningTest()){
                            objXiqComp.username = 'test@test.com';
                            objXiqComp.token = 'axu4-1263374a44d9ebe98a0f';
                        }   
                        
                        objWrapperList.add(objXiqComp);
                    }
                    mapOfAccounts.put(s, objWrapperList);   
                }
            }
            
            List<Map<String,List<XiqCompany>>> mapInList = new List<Map<String,List<XiqCompany>>>();
            mapInList.add(mapOfAccounts);
            
            String companyNm = JSON.serialize(mapInList);
            
            string form64 = '';
            form64 += vNHttpFormBuilder.WriteBoundary();
            
            if ( xiqToken != null ) {
                form64 += vNHttpFormBuilder.WriteBodyParameter('username', setupUser.Notify_Email__c); 
                form64 += vNHttpFormBuilder.WriteBoundary();
                form64 += vNHttpFormBuilder.WriteBodyParameter('token', setupUser.token__c); 
                form64 += vNHttpFormBuilder.WriteBoundary();
                form64 += vNHttpFormBuilder.WriteBodyParameter('companiesJSON', companyNm);
            }
            
            form64 += vNHttpFormBuilder.WriteBoundary();
            blob formBlob = EncodingUtil.base64Decode(form64);
            
            Http http = new Http();
            
            HttpRequest request = new HttpRequest();
            request.setEndpoint('https://api-upgrade.xiq.io/v2/salesforcesynccompaniesv1/');
            request.setMethod('POST');
            request.setTimeout(60000);
            
            String contentType = vNHttpFormBuilder.GetContentType();
            request.setHeader('Content-Type',contentType);
            
            request.setBodyAsBlob(formBlob);
            
            xiQErrorLogger logger = new xiQErrorLogger();
            
            HttpResponse response = new HttpResponse();
            
            if (!Test.isRunningTest()) {
                response = http.send(request);
            } else {
                response.setStatusCode(200);
                response.setBody('{"status":"success","message":"Sync Companies Request processed","companies":[{"companyName":"SAP","website":"sap.com","salesforce_id":123,"xiq_company_id":102},{"companyName":"Microsoft%20Corporation","website":"microsoft.com","Salesforce_id":456,"xiq_company_id":109}]}');
            }
            
            String JasonResponse = response.getBody();
            
            Map<String,Account> accountMap = new Map<String,Account>();
            Set<String> accountIDsSet = new Set<String>();
            Set<Account> accntList = new Set<Account>();
            
            if (response.getStatusCode() != 200) {
                
                xiQErrorLogger.mailError('xiQSync',107,'HTTP Error','Callout to xiQ Backend Failed in xiQSync Class');
                
            } else {
                
                XIQCompanyResponseWrapper objResponseWrap = (XIQCompanyResponseWrapper) JSON.deserialize(JasonResponse, XIQCompanyResponseWrapper.class);
                                
                Map<String,XIQCompanyResponseWrapper.cls_companies[]>userObj = objResponseWrap.companies[0];
                List<XIQCompanyResponseWrapper.cls_companies> fullCompaniesList = new List<XIQCompanyResponseWrapper.cls_companies>();
                
                for (String s : userObj.keyset()) {
                    fullCompaniesList.addAll(userObj.get(s));
                }
                
                for (XIQCompanyResponseWrapper.cls_companies company : fullCompaniesList) {
                    accountIDsSet.add(company.salesforce_id);
                }
                
                for(Account objAcc: [SELECT ID,XIQ_Company_ID__c FROM Account WHERE ID IN : accountIDsSet LIMIT 1500]){
                    accountMap.put(objAcc.ID,objAcc);
                }
                
                
                for (XIQCompanyResponseWrapper.cls_companies company : fullCompaniesList) {
                    if(accountMap.keyset().contains(company.salesforce_id)) {
                        Account objAccount = accountMap.get(company.salesforce_id);
                        if(company.xiq_company_id > 0){
                            if (Schema.sObjectType.Account.fields.XIQ_Company_ID__c.isUpdateable()){
                                objAccount.XIQ_Company_ID__c = String.valueOf(company.xiq_company_id);
                            }
                        }
                        accntList.add(objAccount);  
                	}
                }
            } 
            
            List<Account> newList = new List<Account>();
            
            for (Account acc : accntList) {
                newList.add(acc);
            }
            
            if (accntList.size() > 0)
                update newList;
               
            companiesProcessed = accntList.size();
            
        } catch (Exception ex) {
            xiQErrorLogger.mailError('xiQSync',147,ex.getTypeName(),ex.getMessage());
        } 
        
        return companiesProcessed;
        
    }
    
    
    //Method which Request to sync single User to XIQ and save the token to XIQ token object received in the response 
    public static xiQ_User_Tokens__c xiqLogin(String OrganizationId,String SessionId,String userId){
        
        String salesForceLoginUrl = 'https://login.salesforce.com/id/'+OrganizationId+'/'+userId;
        
        Boolean runningInASandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
        
        if (!runningInASandbox) {
            salesForceLoginUrl = 'https://login.salesforce.com/id/'+OrganizationId+'/'+userId;
        }else{
            salesForceLoginUrl = 'https://test.salesforce.com/id/'+OrganizationId+'/'+userId;
        }       
        
        
        string form64 = '';
        form64 += vNHttpFormBuilder.WriteBoundary();
        form64 += vNHttpFormBuilder.WriteBodyParameter('salesForceLoginUrl', salesForceLoginUrl); 
        form64 += vNHttpFormBuilder.WriteBoundary();
        form64 += vNHttpFormBuilder.WriteBodyParameter('salesForceToken', SessionId);  
        form64 += vNHttpFormBuilder.WriteBoundary();
        
        blob formBlob = EncodingUtil.base64Decode(form64);
        
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint('https://api-upgrade.xiq.io/salesforcelogin/');
        request.setMethod('POST');
        
        string contentType = vNHttpFormBuilder.GetContentType();
        request.setHeader('Content-Type',contentType);                
        request.setBodyAsBlob(formBlob);
        HttpResponse response = new HttpResponse();
        String jsonResponse = '';
        
        if (!Test.isRunningTest()){
            response = http.send(request);        
        } else {
            response.setStatusCode(200);
            response.setBody('{"fullname":"Saad Khan","notifyemail":"skhan08@xiqinc.com","subscription":"Subscribed","status":"success","message":"Login successful","token":"in8j-2c31c2b9e1f46d4","linkedinusername":"","twitterusername":"","companiesexist":"True","companiescount":10,"industriesexist":"True","Industriescount":10,"plan":"Free","appName":"SalesForce","deviceToken":"SalesForce Client refreshToken"}');
        }
        
        jsonResponse=response.getBody();
        
        xiQIncSF1__xiQ_User_Tokens__c objToken = new xiQIncSF1__xiQ_User_Tokens__c();
        
        if (response.getStatusCode() != 200) {
            
        } else {
            jsonResponse=response.getBody();
            
            XiqLoginResponseWrapper objXiqLoginResponseWrapper =(XiqLoginResponseWrapper) System.JSON.deserialize(jsonResponse, XiqLoginResponseWrapper.class);
            
            if (Schema.sObjectType.xiQ_User_Tokens__c.fields.Token__c.isAccessible() && (Schema.sObjectType.xiQ_User_Tokens__c.fields.Token__c.IsUpdateable() || Schema.sObjectType.xiQ_User_Tokens__c.fields.Token__c.isCreateable())){
                objToken.Token__c = objXiqLoginResponseWrapper.token;
            }
            
            if (Schema.sObjectType.xiQ_User_Tokens__c.fields.Token__c.isAccessible() && (Schema.sObjectType.xiQ_User_Tokens__c.fields.Token__c.IsUpdateable() || Schema.sObjectType.xiQ_User_Tokens__c.fields.Token__c.isCreateable())){
                objToken.User_ID__c = userId;
            }
            
            if (Schema.sObjectType.xiQ_User_Tokens__c.fields.Token__c.isAccessible() && (Schema.sObjectType.xiQ_User_Tokens__c.fields.Token__c.IsUpdateable() || Schema.sObjectType.xiQ_User_Tokens__c.fields.Token__c.isCreateable())){
                objToken.Notify_Email__c = objXiqLoginResponseWrapper.notifyemail;
            }
            
            if (Schema.sObjectType.xiQ_User_Tokens__c.fields.Token__c.isAccessible() && (Schema.sObjectType.xiQ_User_Tokens__c.fields.Token__c.IsUpdateable() || Schema.sObjectType.xiQ_User_Tokens__c.fields.Token__c.isCreateable())){
                objToken.Name = objXiqLoginResponseWrapper.fullName;
            }
            if (Schema.sObjectType.xiQ_User_Tokens__c.fields.Token__c.isAccessible() && (Schema.sObjectType.xiQ_User_Tokens__c.fields.Token__c.IsUpdateable() || Schema.sObjectType.xiQ_User_Tokens__c.fields.Token__c.isCreateable())){
                objToken.Reason__c = objXiqLoginResponseWrapper.reason;
            }
            
        }
        
        return objToken;
    }
    
    
    //Method which Request to sync Multiple Active Users to XIQ and save the token to XIQ token object received in the response. 
    public static List<xiQ_User_Tokens__c> xiqMultipleLogin(String OrganizationId,String SessionId,String userId,List<User> activeUser){
        
        String salesForceLoginUrl = 'https://login.salesforce.com/id/'+OrganizationId+'/'+userId;
        
        Boolean runningInASandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
        
        if (!runningInASandbox) {
            salesForceLoginUrl = 'https://login.salesforce.com/id/'+OrganizationId+'/'+userId;
        }else{
            salesForceLoginUrl = 'https://test.salesforce.com/id/'+OrganizationId+'/'+userId;
        }
        
        List<UserWrapper>  userWrapperList =  new List<UserWrapper>();
        Set<String> notLicenced = new Set<String>();
        
        for (User user: activeUser) {
            UserWrapper  objUserWrapper =  new UserWrapper();
            objUserWrapper.Name = user.Name;
            objUserWrapper.Email = user.Email;
            objUserWrapper.Islicensed = true;
            userWrapperList.add(objUserWrapper);   
            notLicenced.add(user.ID);
        } 
        
        
        String userJsonString = JSON.Serialize(userWrapperList);
        
        string form64 = '';
        form64 += vNHttpFormBuilder.WriteBoundary();
        form64 += vNHttpFormBuilder.WriteBodyParameter('salesForceLoginUrl', salesForceLoginUrl);
        form64 += vNHttpFormBuilder.WriteBoundary();
        form64 += vNHttpFormBuilder.WriteBodyParameter('salesForceToken',SessionId);
        form64 += vNHttpFormBuilder.WriteBoundary();
        form64 += vNHttpFormBuilder.WriteBodyParameter('usersJSON', userJsonString);  
        form64 += vNHttpFormBuilder.WriteBoundary();
        
        
        blob formBlob = EncodingUtil.base64Decode(form64);
        
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint('https://api-upgrade.xiq.io/v2/salesforcemultipleloginv1/');
        request.setMethod('POST');
       	request.setTimeout(60000);
        
        string contentType = vNHttpFormBuilder.GetContentType();
        
        request.setHeader('Content-Type',contentType);                
        request.setBodyAsBlob(formBlob);
        
        HttpResponse response = new HttpResponse(); 
        if(!Test.isRunningTest()){
            response = http.send(request);
        }else{
            response.setStatusCode(200);
            response.setBody('{"status":"success","message":"Users Successfully Created","users":[{"name":"Saad Khan","email":"skhan08@xiqinc.com","token":"ljlahbhe307023r5"},{"name":"Saqib Ali","email":"sali06@xiqinc.com","token":"ljlahbhe307023r5"}]}');
        }
        
        String jsonResponse=response.getBody();
                
        List<xiQIncSF1__xiQ_User_Tokens__c> userTokenList = new List<xiQIncSF1__xiQ_User_Tokens__c>();
        
        if (response.getStatusCode() != 200) {
            
        } else {
            
            //Repeated code, check line 258. jsonResponse is already set to response's Body above.
            jsonResponse=response.getBody();
            
            // Casting blob 
            XiqLoginResponseWrapper objXiqLoginResponseWrapper =(XiqLoginResponseWrapper) System.JSON.deserialize(jsonResponse, XiqLoginResponseWrapper.class);
            
            Set<String> emailSet = new Set<String>();
            
            for(XiqLoginResponseWrapper.cls_users userToken : objXiqLoginResponseWrapper.users){
                emailSet.add(userToken.email);
            }
            
            Map<String,User> userMap = new Map<String,User>();
            for(User objUser : [SELECT ID, Email FROM User WHERE Email IN : emailSet]){
                userMap.put(objUser.Email,objUser);
            }
            
            for(XiqLoginResponseWrapper.cls_users userToken : objXiqLoginResponseWrapper.users){
                xiQIncSF1__xiQ_User_Tokens__c objToken = new xiQIncSF1__xiQ_User_Tokens__c();
                
                objToken.Token__c = userToken.token;
                
                if(userMap.containsKey(userToken.email))
                    objToken.User_ID__c = userMap.get(userToken.email).ID;
                
                objToken.Notify_Email__c = userToken.email;
                
                objToken.Name = userToken.name;
                objToken.Reason__c = userToken.reason;
                String xiQtokenString = userToken.token;
                
                if (xiQtokenString.length() > 0) {
                    objToken.IsLicensed__c = true; 
                } else {  
                 	objToken.IsLicensed__c = false;
                }                     
                userTokenList.add(objToken);    
            }
        }
        
        return userTokenList;
    }
  
    
    public class UserWrapper{
        public String name; 
        public String email;
        public Boolean Islicensed;
        public String reason;
    }
    
    public class UserCompanies{
        public Integer total_user_companies; 
    }
    
}