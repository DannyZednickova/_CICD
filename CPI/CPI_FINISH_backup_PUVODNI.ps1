param(
    [string]$BRANCH_NAME,
    [string]$REPO_NAME,
    [string]$RELEASE_VERSION,
    [string]$TEAM_PROJECT,
    [string]$TEAM_URI,
    [string]$PAT
)

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
function GetPullRequestStatus {
    param([string]$prId)

    $Uri = "$PROJECT_URI/_apis/git/repositories/$REPO_NAME/pullRequests/$prId?api-version=6.0"
    $resp = Invoke-RestMethod -Uri $Uri -Headers $Headers -UseBasicParsing

    return @{
        Status      = $resp.status       # active | completed | abandoned
        MergeStatus = $resp.mergeStatus  # succeeded | conflicts | queued | notSet
    }
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
$pr = GetPullRequestStatus -prId $prId
if ($pr.MergeStatus -eq "conflicts") {
    Write-Error "❌ PR $prId has merge conflicts. Resolve manually in Azure DevOps."
}
while ($pr.Status -ne "active") {
    Start-Sleep -Seconds 5
    $pr = GetPullRequestStatus -prId $prId
    Write-Host "PR Status: $($pr.Status), MergeStatus: $($pr.MergeStatus)"
}

echo "COMPLETING PULL REQUEST TO MERGE $BRANCH_NAME IN DEVELOP..."
CompletePullRequest -resp $response
$pr = GetPullRequestStatus -prId $prId
while ($pr.Status -ne "completed") {
    Start-Sleep -Seconds 5
    $pr = GetPullRequestStatus -prId $prId
    Write-Host "PR Status: $($pr.Status), MergeStatus: $($pr.MergeStatus)"
}



echo "CREATING PULL REQUEST TO MERGE $BRANCH_NAME IN MASTER..."
$response = CreatePullRequest -srcbranch $BRANCH_NAME -trgbranch "master"
$prId = GetPullRequestId -resp $response
$pr = GetPullRequestStatus -prId $prId
if ($pr.MergeStatus -eq "conflicts") {
    Write-Error "❌ PR $prId has merge conflicts. Resolve manually in Azure DevOps."
}
while ($pr.Status -ne "active") {
    Start-Sleep -Seconds 5
    $pr = GetPullRequestStatus -prId $prId
    Write-Host "PR Status: $($pr.Status), MergeStatus: $($pr.MergeStatus)"
}

echo "COMPLETING PULL REQUEST TO MERGE $BRANCH_NAME IN MASTER..."
CompletePullRequest -resp $response
$pr = GetPullRequestStatus -prId $prId
while ($pr.Status -ne "completed") {
    Start-Sleep -Seconds 5
    $pr = GetPullRequestStatus -prId $prId
    Write-Host "PR Status: $($pr.Status), MergeStatus: $($pr.MergeStatus)"
}


# Tag master with version
echo "ADDING NEW TAG WITH NEW VERSION $RELEASE_VERSION TO MASTER BRANCH..."
TagMasterWithVersion
