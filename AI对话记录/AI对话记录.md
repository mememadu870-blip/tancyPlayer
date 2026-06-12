
# first dev
根据`C:\Users\admin\Desktop\gstack` 这个项目的流程，帮我开发一个安卓手机端音乐播放器。你需要帮我考虑主流的功能，比如上一首，下一首，定时停止，自动扫描音乐文件，创建歌单，收藏，重复音频文件提示（按hash计算）等。


# improve 
1. remember my setting for the value of timer interval progressBar
2. hash is so slow, i think there is something wrong with it. please check and improve.
3. add  more setting button  to every music in list replace  the **add to playlist** button. when user tap it,it should pop a menu for user to choose like below
* play next next song
* add to play list 
* send to 
* show more detail
pop a view to show music detail,the quality of the music file,the path ,the size and so on.
and also add a back and delete button. pop warning view, delete when user tap commit.
4. the app sould regedit to system,set it as defual player or in the app list when user tap every music file on android system. 
 

when user long tap a music file.

show a pop view to let user check music 



you no need to build on my local compuer,use  push to github with ssh and trigger actions to build apk.
my github repository: git@github.com:mememadu870-blip/tancyPlayer.git



# 播放器功能改进
1. 设置中启用定时应该自动加入记忆，下次打开也是按之前设置的定时时间自动停止播放。 同样的播放完整歌曲后停止也要自动记忆。
2. 打开APP时不要自动扫描重复音乐，而应该点击时才触发。
3. 点喜爱时，应该自动加入playLists中的喜爱歌单，如不存在应自动创建，如果取消了喜爱，则要从喜爱歌单中对应移除。

做完你不要在本地编译，直接帮我push到github，检测和修复直到成功构建apk,再通知我。