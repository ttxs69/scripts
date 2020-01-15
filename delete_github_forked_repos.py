# pip install PyGithub
from github import Github

# using username and password
g = Github("username", "password")

for repo in g.get_user().get_repos():
    # check forked
    if repo.fork:
        repo.delete()
    else:
        continue
print("done")
