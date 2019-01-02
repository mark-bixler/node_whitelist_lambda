'use strict';

// Load Modules
const AWS = require('aws-sdk')
const fetch = require("node-fetch")

//Set the region
AWS.config.update({region: 'us-west-2'});

// Call AWS Resources
const ec2 = new AWS.EC2();

// Initalize URL Dictionary
const urls = {
  okta:    'https://s3.amazonaws.com/okta-ip-ranges/ip_ranges.json',
  github: 'https://api.github.com/meta'
  }

//*****************************************************************************/
// Get Security Group ID From Event
const deleteExistingRules = async (event) => {
  console.log('REMOVING EXISTING SG RULES')
  var params = { Filters: [{Name: 'tag:t_whitelist', Values:[event['site']]}]};
  const describeSG = await ec2.describeSecurityGroups(params).promise();
  var groupIds = [];
  
  //Remove Ingress Rules for each Group
  for (var group in describeSG.SecurityGroups){ 
    // Store SG ID's to List for Return to other Functions
    groupIds.push(describeSG.SecurityGroups[group].GroupId);
    console.log(`- Working on sg: ${describeSG.SecurityGroups[group].GroupId}`);
    // Set Parameters & Remove SG Ingress Rules
    var params = describeSG.SecurityGroups[group];
    
    if (params.IpPermissions.length > 0) {
      const ipRanges = params.IpPermissions[0]['IpRanges'];
      console.log(`-- This Security Group has ${ipRanges.length} rule(s) to remove`)

      // DELETE Attributes
      delete params.OwnerId;
      delete params.Description;
      delete params.IpPermissionsEgress;
      delete params.VpcId;
      delete params.Tags;
      delete params.IpPermissions[0].UserIdGroupPairs;
      delete params.GroupName;
      delete params.IpPermissions[0].PrefixListIds;
      delete params.IpPermissions[0].Ipv6Ranges;
      try{
        const deleteResponse = await ec2.revokeSecurityGroupIngress(params).promise();
        console.log(' ...rules removed successfully!')
      }
      catch (error){
        console.log(`- Something went wrong getting ingress rules: ${error}`)
      }
    }
    else{
      console.log('-- No Ingress Rules Found');
    }
  
  } 
  return groupIds;
 };
 
//*****************************************************************************/
// Get IP's From Event
const getWhitelistIps = async (event) => {
  console.log('ADDING WHITELISTED IPS')
  if ('site' in event){
    var site = event['site']
    if (site == 'okta' || site == 'github'){
      return await fetch(urls[site])
      .then(function(res){return res.json();})
      .then(function(json){
        var obj = {"site": site, "ips": json}
        return obj
        })
    }
  }
else
    return "Site not yet Supported!"
}

//*****************************************************************************/
// Iterate over IP's and Update SG
const updateSgRules = async (data, sgs) => {
  
  // Get Secruity Group ID
  for (var group in sgs ){
    
    switch(data['site']){
    // OKTA ///////////////////////////////////////////////////////
      case 'okta': 
        var oktaIps = []
          for (var i in data['ips']){
            var ip_ranges = data['ips'][i];
            for (var j in ip_ranges){
              var ip = ip_ranges[j]
              for (var k in ip){
                oktaIps.push({"CidrIp": ip[k], 
                "Description": "**AUTOMATED ** OKTA IP for Auth"})
            }}} //forforfor
        
        // Call Dedup Function
        var oktaRange = dedupeIPs(oktaIps);
        // Limit Rule to 50
        var oktaLimitedRange = oktaRange.slice(0,50);
        
        // Store All Values
        var oktaParams = {
          GroupId: sgs[group],
          IpPermissions: [{
            FromPort: 443,
            IpProtocol: "tcp",
            IpRanges: oktaLimitedRange,
            ToPort: 443
            }] //IpPermissions
          }; //oktaParams

        try{
          const addRes = await ec2.authorizeSecurityGroupIngress(oktaParams).promise();
          console.log(`- Successfully added new okta rules to ${sgs[group]}`)
          }
        catch (error){
          console.log(`- Something went wrong adding okta ingress rules: ${error}`)
          }
        break;
      // GITHUB ////////////////////////////////////////////////
      case 'github':
        var githubIps = [];  
        for (var i in data['ips']){
          if (i == 'git' ||
              i == 'hooks' ||
              i == 'pages'){
            var ip_ranges = data['ips'][i];
            for (var j in ip_ranges){
              var ip = ip_ranges[j]
              githubIps.push({"CidrIp": ip, 
                "Description": "**AUTOMATED ** GITHUB IP for Auth"})
          };};}; //for-if-for
        
        // Call Dedup Function
        var githubUnique = dedupeIPs(githubIps);
        
        // Store All Values
        var githubParams = {
          GroupId: sgs[group],
          IpPermissions: [{
            FromPort: 443,
            IpProtocol: "tcp",
            IpRanges: githubUnique,
            ToPort: 443
            }] //IpPermissions
          }; //githubParams
        
        try{
          const addRes = await ec2.authorizeSecurityGroupIngress(githubParams).promise();
          console.log(`- Successfully added new github rules to ${sgs[group]}`);
          }
        catch (error){
          console.log(`- Something went wrong adding github ingress rules: ${error}`)
          }
        break;
      }; //switch
    }; //for loops
}; // getIpsUpdateSg 

//*****************************************************************************/
//DeDup List of IP's
function dedupeIPs(dict) {
  var hashTable = {};
  return dict.filter(function (el) {
    var key = JSON.stringify(el);
    var match = Boolean(hashTable[key]);
    return (match ? false : hashTable[key] = true);
  });
};

//*****************************************************************************/
// MAIN FUNCTION
//*****************************************************************************/
exports.handler = (event, context) => {
  var sgs;
  deleteExistingRules(event)
  .then(_sgs => {sgs = _sgs; return getWhitelistIps(event)})
  .then(ips => {updateSgRules(ips, sgs);});
}
