$map = Import-Csv "F:\tools\repo_mapping.csv"

$extraInB = $map | Where-Object { $_.InRepoB -eq 'True' -and $_.InRepoA -eq 'False' }
$missingInB = $map | Where-Object { $_.InRepoA -eq 'True' -and $_.InRepoB -eq 'False' }
$drift = $map | Where-Object {
    $_.InRepoA -eq 'True' -and $_.InRepoB -eq 'True' -and $_.A_Hash -ne '' -and $_.B_Hash -ne '' -and $_.A_Hash -ne $_.B_Hash
}

'=== Extra in RepoB (candidates for deletion) ==='
$extraInB | Select-Object Path, B_FullPath, B_LastWrite, B_Size

'=== Missing in RepoB (should be copied from RepoA) ==='
$missingInB | Select-Object Path, A_FullPath, A_LastWrite, A_Size

'=== Drift (same path, different content) ==='
$drift | Select-Object Path, A_LastWrite, B_LastWrite, A_Size, B_Size
