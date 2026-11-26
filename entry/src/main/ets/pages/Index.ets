import { HomePage } from './HomePage';
import { AddTodoPage } from './AddTodoPage';
import { NetworkPage } from './NetworkPage';

// 入口：Navigation 导航容器，注册目标页并使用路由入栈出栈
@Entry
@ComponentV2
struct Index {
  @Local navPathStack: NavPathStack = new NavPathStack();

  // navDestination 构建器：按路由名渲染目标页面
  @Builder
  pageMap(name: string, param: Object) {
    if (name === 'Home') {
      HomePage({ navPathStack: this.navPathStack })
    } else if (name === 'Add') {
      AddTodoPage({ navPathStack: this.navPathStack })
    } else if (name === 'Network') {
      NetworkPage({ navPathStack: this.navPathStack })
    }
  }

  build() {
    Navigation(this.navPathStack) {
      // 导航根：首页
      HomePage({ navPathStack: this.navPathStack })
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
  }
}
