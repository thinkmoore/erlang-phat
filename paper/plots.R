library(ggplot2)
times <- read.csv("~/Documents/schoolwork/cs260/erlang-phat/paper/times.csv")

ggplot(times, aes(N..total.nodes., Store.Time..ms., label = Label, group = Group)) + 
  geom_line() +
  geom_text(vjust=-1.25,size=4)+ ylim(0,2000) + xlim(0, 35) + 
  theme_bw() + xlab("Number of Total Nodes") + ylab("Store Time (ms)") + geom_point()

ggplot(times, aes(N..total.nodes., Fetch.Time..ms., label = Label, group = Group)) + 
  geom_line() +
  geom_text(vjust=-1.25,size=4)+ ylim(0,2000) + xlim(0, 35) + 
  theme_bw() + xlab("Number of Total Nodes") + ylab("Fetch Time (ms)") + geom_point()
