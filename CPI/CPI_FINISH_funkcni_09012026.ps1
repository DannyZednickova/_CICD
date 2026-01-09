$BRANCH_NAME     = "release/deb-9.43.0"
$REPO_NAME       = "deb"
$RELEASE_VERSION = "9.43.0"
$TEAM_PROJECT    = "CrossPark"
$TEAM_URI        = "https://devops.cross.cz/Development/"
$PAT             = "****"



$PROJECT_URI=$TEAM_URI + $TEAM_PROJECT


# MERGE and TAG deb

$pair = ":"+$PAT
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$basicAuthValue = "Basic $encodedCreds"
$Headers = @{
    Authorization = $basicAuthValue
    ContentType="charset=utf -8"
}

# FUNCTIONS ---------------------------------------------------------------------------------------------------------------------------------------
# FUNCTION - Get objectId with parameter: branch
function GetObjId{
    Param([string]$branch)
    
    $RESPONSEID=@(Invoke-WebRequest -Uri "$PROJECT_URI/_apis/git/repositories/$REPO_NAME/refs?filter=heads/$branch&peeltags=true" -Headers $Headers -UseBasicParsing)
    [string]$content = $RESPONSEID
    [int]$pos=$content.IndexOf("objectId")
    $id=$content.Substring($pos+11, 40)
    return $id
}

#tagexists 
function TagExists {
    Param([string]$tagName)

    $uri = "$PROJECT_URI/_apis/git/repositories/$REPO_NAME/refs?filter=tags/$tagName&api-version=6.0"
    $resp = Invoke-RestMethod -Uri $uri -Headers $Headers -Method GET
    return ($resp.count -gt 0)
}


# FUNCTION - Get merge Id
function GetMergeId{
    Param([string]$resp)
    
    [string]$content = $resp
    [int]$pos=$content.IndexOf("lastMergeSourceCommit")
    $mergeId=$content.Substring($pos+36, 40)
    return $mergeId
}

# FUNCTION - Create pull request with parameter branch
function CreatePullRequest{
    Param([string]$srcbranch, [string]$trgbranch)
    
    $body = @{
        "sourceRefName"="refs/heads/$srcbranch"
        "targetRefName"="refs/heads/$trgbranch"
        "title"="merge $srcbranch to $trgbranch"
        "description"="CI/CD merge $srcbranch to $trgbranch"
    }
    $jsonBody = $body | ConvertTo-Json
    $POST_RESPONSE=@(Invoke-WebRequest -Uri "$PROJECT_URI/_apis/git/repositories/$REPO_NAME/pullRequests?api-version=6.0" -Method "POST" -Headers $Headers -ContentType "application/json" -Body $jsonBody -UseBasicParsing)
    Start-Sleep -Seconds 5
    return $POST_RESPONSE
}

# FUNCTION - Get pull request Id with parameter: response
function GetPullRequestId{
    Param([string]$resp)

    [string]$content = $resp
    [int]$pos=$content.IndexOf("pullRequestId")
    [int]$cdId=$content.IndexOf("codeReviewId")
    [int]$prId=$content.Substring($pos+15, $cdId-$pos-17)
    [string]$prId=[int]$prId
    return $prId
}

# FUNCTION - Get Pull Request Status
function GetPullRequestStatus{
    Param([string]$prId)

    $Uri = "$PROJECT_URI/_apis/git/repositories/$REPO_NAME/pullRequests/$prId" + "?api-version=6.0"
    $RESP=@(Invoke-WebRequest -Uri $Uri -Headers $Headers -UseBasicParsing)
    [string]$content = $RESP
    [int]$pos=$content.IndexOf("status")
    [int]$end=$content.IndexOf("createdBy")
    $status=$content.Substring($pos+9, $end-$pos-12)
    return $status
}

# FUNCTION - Complete Pull Request
function CompletePullRequest{
    Param([string]$resp)

    $mergeId = GetMergeId -resp $resp
    $prId = GetPullRequestId -resp $resp
    $body = @{
        "status"="completed"
        "lastMergeSourceCommit"=@{"commitId"="$mergeId"}
    }
    $jsonBody = $body | ConvertTo-Json
    $Uri="$PROJECT_URI/_apis/git/repositories/$REPO_NAME/pullRequests/$prId" + "?api-version=6.0-preview.1"
    $PATCH_RESPONSE=@(Invoke-WebRequest -Uri $Uri -Method "PATCH" -Headers $Headers -ContentType "application/json" -Body $jsonBody -UseBasicParsing)
    [string]$content = $PATCH_RESPONSE
    Start-Sleep -Seconds 5
}


# FUNCTION - TagMasterWithVersion
function TagMasterWithVersion{

     if (TagExists -tagName $RELEASE_VERSION) {
        Write-Output "TAG $RELEASE_VERSION už existuje, krok tagování přeskočen."
        
        return
    }


    $objId = GetObjId -branch master
    $body = @{
        "message"="CICD tag for version $RELEASE_VERSION"
        "taggedObject"=@{"objectId"="$objId"}
        "name"="$RELEASE_VERSION"
    }

    $jsonBody = $body | ConvertTo-Json
    $POST_RESPONSE=@(Invoke-WebRequest -Uri "$PROJECT_URI/_apis/git/repositories/$REPO_NAME/annotatedtags?api-version=6.0-preview.1" -Method "POST" -Headers $Headers -ContentType "application/json" -Body $jsonBody -UseBasicParsing)
}
# FUNCTIONS end -----------------------------------------------------------------------------------------------------------------------------------

echo "CREATING PULL REQUEST TO MERGE $BRANCH_NAME IN DEVELOP..."
$response = CreatePullRequest -srcbranch $BRANCH_NAME -trgbranch "develop"
$prId = GetPullRequestId -resp $response
$status = GetPullRequestStatus -prId $prId
while($status -ne "active"){
    $status = GetPullRequestStatus -prId $prId
}

echo "COMPLETING PULL REQUEST TO MERGE $BRANCH_NAME IN DEVELOP..."
CompletePullRequest -resp $response
$status = GetPullRequestStatus -prId $prId
while($status -ne "completed"){
    Start-Sleep -Seconds 3
    $status = GetPullRequestStatus  -prId $prId
}



echo "CREATING PULL REQUEST TO MERGE $BRANCH_NAME IN MASTER..."
$response = CreatePullRequest -srcbranch $BRANCH_NAME -trgbranch "master"
$prId = GetPullRequestId -resp $response
$status = GetPullRequestStatus -prId $prId
while($status -ne "active"){
    $status = GetPullRequestStatus -prId $prId
}

echo "COMPLETING PULL REQUEST TO MERGE $BRANCH_NAME IN MASTER..."
CompletePullRequest -resp $response
$status = GetPullRequestStatus -prId $prId
while($status -ne "completed"){
    Start-Sleep -Seconds 3
    $status = GetPullRequestStatus -prId $prId
}

# Tag master with version
echo "ADDING NEW TAG WITH NEW VERSION $RELEASE_VERSION TO MASTER BRANCH..."
TagMasterWithVersion