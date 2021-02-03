/*
Author        	| Date             		| Description
Abdullah       | 3/12/2020  	  | Release 1.1
*/


global without sharing class BatchSyncUsers implements Database.Batchable<sObject>,Database.AllowsCallouts,Database.Stateful{
    
    private String sessionId;
    
    // Global variables for tokens acquired from xiQ backend
    // and store successful and total records processed
    global List<xiQIncSF1__xiQ_User_Tokens__c> userTokensList;
    global Integer totalCount;
    global Integer successCount;
    
    // Class constructor
    // Initialising total Count of records processed and successful records processed.
    global BatchSyncUsers() {
        totalCount = 0;
        successCount = 0;
        sessionId = UserInfo.getSessionID();
    }
    
    //Querying all Active Users
    global Database.QueryLocator start(Database.BatchableContext BC) {
        
        Set<String> userEmailSet = new Set<String>();
        Set<String> userIdSet = new Set<String>();
        List<User> uList = new List<User>();
        
        for (xiQIncSF1__xiQ_User_Tokens__c token : [SELECT Notify_Email__c FROM xiQIncSF1__xiQ_User_Tokens__c WHERE Notify_Email__c !=null LIMIT 10000]) {
            userEmailSet.add(token.Notify_Email__c);        
        }
        
        Boolean runningInASandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
        Boolean isDevEdition = [Select OrganizationType From Organization LIMIT 1].OrganizationType.contains('Developer');
        List<PackageLicense> licenseList  = [SELECT id,NamespacePrefix FROM PackageLicense where NamespacePrefix = 'xiQIncSF1'];
        
        if (licenseList != null && licenseList.size() > 0) {
            // is Production instance
            uList = [SELECT Id,Name FROM User where IsActive = true AND Id in (SELECT UserId FROM UserPackageLicense WHERE (PackageLicense.NamespacePrefix = 'xiQIncSF1'))];
        } else {
            // is Sandbox instance
            uList = [SELECT Id,Name FROM User where IsActive = true LIMIT 10];
        }
        
        for (User licensedUsers : uList) {
            userIdSet.add(licensedUsers.Id);
        }
        
        // Get list of users with no licenses
        userTokensList = new List<xiQIncSF1__xiQ_User_Tokens__c>();
        string query = 'Select Id, Name, Email from User WHERE Id IN: userIdSet AND isActive = True LIMIT 10000 ';       
        
        return Database.getQueryLocator(query);
    }
    
    
    //Which sync all Active Users from salesforce to XIQ and create the token records.
    global void execute(Database.BatchableContext BC, List<sObject> scope) {
        
        try{
            if (scope.size() > 0) {
                userTokensList = XiqSync.xiqMultipleLogin(UserInfo.getOrganizationId(),sessionId,UserInfo.getUserId(),(List<User>)scope);
                if (userTokensList.size()>0) {                    
                    database.insert(userTokensList, false);
                }
            }
            
            totalCount += scope.size();
            successCount += scope.size();
            
        } catch (Exception ex) {
            successCount -= scope.size();
            xiQErrorLogger.mailError('BatchSyncUsers',73,ex.getTypeName(),ex.getMessage());
        }
    }
    
    
    // Calling BatchSyncCompanies class and passing current class' data.
    global void finish(Database.BatchableContext BC){
        AsyncApexJob a = [Select Id, Status, CreatedBy.Email from AsyncApexJob where Id =:BC.getJobId()];
        Id syncCompaniesJob = Database.executeBatch(new BatchSyncCompanies(totalCount,successCount),20);        
    } 
}